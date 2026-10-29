import CLibArchive
import Foundation
import ZeigCore

/// libarchive, used directly through its C API (imported as `CLibArchive`).
///
/// Handles what 7-Zip doesn't create: compressed tars, single-file zstd/lz4/lzip/lzma/.Z,
/// ISO, cpio, xar and ar (see `BackendRouter`). It's also the fallback reader when 7-Zip
/// can't open a file. libarchive streams: it reads entries in order and can't seek back,
/// so every operation is one pass over the archive.
public struct LibArchiveBackend: ArchiveBackend {
    public let id = BackendID.libArchive

    public init() {}

    public var version: String {
        // "libarchive 3.8.10 zlib/1.2.12 liblzma/5.8.4 …" → "3.8.10"
        let full = String(cString: archive_version_string())
        return full.split(separator: " ").dropFirst().first.map(String.init) ?? full
    }

    /// The full version line with the compression libraries, for Settings → Backends.
    public var versionDetails: String { String(cString: archive_version_details()) }

    // MARK: Reading

    public func list(_ archive: URL, format: ArchiveFormat?, password: String?) throws(ArchiveError) -> ArchiveContents {
        try withUTF8Locale { () throws(ArchiveError) in try listEntries(archive, format: format, password: password) }
    }

    private func listEntries(_ archive: URL, format: ArchiveFormat?, password: String?) throws(ArchiveError) -> ArchiveContents {
        var entries: [ArchiveEntry] = []
        var info = ArchiveInfo()
        try read(archive, format: format, password: password) { (reader, entry, index) throws(ArchiveError) in
            if index == 0 { info = describe(reader) }
            entries.append(makeEntry(entry, index: index, archive: archive, format: format))
            return .skip
        }
        ZeigLog.debug("libarchive", "\(archive.lastPathComponent): \(info.formatName ?? "?"), \(entries.count) entries, filters \(info.method ?? "none")")
        return ArchiveContents(entries: entries, info: info)
    }

    /// The container and compression libarchive detected (known once the first header is read).
    private func describe(_ reader: OpaquePointer) -> ArchiveInfo {
        var filters: [String] = []
        for index in 0..<max(0, archive_filter_count(reader)) {
            if let name = archive_filter_name(reader, index).map({ String(cString: $0) }), name != "none" {
                filters.append(name)
            }
        }
        return ArchiveInfo(
            formatName: archive_format_name(reader).map { String(cString: $0) },
            method: filters.isEmpty ? nil : filters.joined(separator: " + ")
        )
    }

    public func extract(
        _ archive: URL, format: ArchiveFormat?, to destination: URL, entries: [ArchiveEntry]?,
        password: String?, progress: ArchiveProgress
    ) throws(ArchiveError) {
        try withUTF8Locale { () throws(ArchiveError) in
            try extractEntries(archive, format: format, to: destination, entries: entries, password: password, progress: progress)
        }
    }

    private func extractEntries(
        _ archive: URL, format: ArchiveFormat?, to destination: URL, entries: [ArchiveEntry]?,
        password: String?, progress: ArchiveProgress
    ) throws(ArchiveError) {
        let wanted = entries.map { Set($0.map(\.index)) }
        let total = fileSize(archive)
        try read(archive, format: format, password: password) { (reader, entry, index) throws(ArchiveError) in
            guard wanted?.contains(index) ?? true else { return .skip }
            let item = makeEntry(entry, index: index, archive: archive, format: format)
            guard !item.isSymlink, let relative = item.sanitizedPath else { return .skip }
            let target = destination.appendingPathComponent(relative)
            if item.isDirectory {
                try createDirectory(target)
                return .skip
            }
            try createDirectory(target.deletingLastPathComponent())
            try writeData(of: reader, to: target, progress: progress, total: total)
            setAttributes(of: target, from: entry)
            return .done
        }
    }

    public func test(_ archive: URL, format: ArchiveFormat?, password: String?, progress: ArchiveProgress) throws(ArchiveError) {
        let total = fileSize(archive)
        try withUTF8Locale { () throws(ArchiveError) in try testEntries(archive, format: format, password: password, progress: progress, total: total) }
    }

    private func testEntries(_ archive: URL, format: ArchiveFormat?, password: String?, progress: ArchiveProgress, total: UInt64) throws(ArchiveError) {
        try read(archive, format: format, password: password) { (reader, entry, _) throws(ArchiveError) in
            // Reading every block makes libarchive check the data (CRCs, decoding errors).
            try drain(reader, progress: progress, total: total)
            return .done
        }
    }

    private enum EntryAction { case skip, done }

    /// Opens `url`, calls `visit` for each entry, closes. Single-file formats are read as
    /// libarchive's "raw" format (one entry holding the decompressed data).
    private func read(
        _ url: URL, format: ArchiveFormat?, password: String?,
        visit: (OpaquePointer, OpaquePointer, Int) throws(ArchiveError) -> EntryAction
    ) throws(ArchiveError) {
        guard let reader = archive_read_new() else { throw .other(detail: "libarchive: out of memory") }
        defer { archive_read_free(reader) }
        archive_read_support_filter_all(reader)
        if format?.isSingleFile == true {
            archive_read_support_format_raw(reader)
        } else {
            archive_read_support_format_all(reader)
        }
        if let password, !password.isEmpty { archive_read_add_passphrase(reader, password) }
        guard archive_read_open_filename(reader, url.path, 64 * 1024) == ARCHIVE_OK else {
            throw readError(reader, opening: true)
        }

        var index = 0
        var entry: OpaquePointer?
        while true {
            let status = archive_read_next_header(reader, &entry)
            if status == ARCHIVE_EOF { break }
            guard status == ARCHIVE_OK || status == ARCHIVE_WARN, let entry else {
                throw readError(reader, opening: index == 0)
            }
            if archive_entry_is_encrypted(entry) != 0, password == nil || password!.isEmpty {
                throw .passwordRequired
            }
            if try visit(reader, entry, index) == .skip {
                archive_read_data_skip(reader)
            }
            index += 1
        }
    }

    private func makeEntry(_ entry: OpaquePointer, index: Int, archive: URL, format: ArchiveFormat?) -> ArchiveEntry {
        let type = UInt32(archive_entry_filetype(entry))
        var path = (archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry)).map { String(cString: $0) } ?? ""
        // The raw format calls its one entry "data"; name it after the archive instead.
        if format?.isSingleFile == true { path = FileNaming.decompressedName(for: archive) }
        return ArchiveEntry(
            index: index,
            path: path,
            size: archive_entry_size_is_set(entry) != 0 ? UInt64(max(0, archive_entry_size(entry))) : 0,
            modified: archive_entry_mtime_is_set(entry) != 0
                ? Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry))) : nil,
            isDirectory: type == FileType.directory || path.hasSuffix("/"),
            isEncrypted: archive_entry_is_encrypted(entry) != 0,
            isSymlink: type == FileType.symlink
        )
    }

    private func writeData(of reader: OpaquePointer, to target: URL, progress: ArchiveProgress, total: UInt64) throws(ArchiveError) {
        // Replace, never write through, whatever is there (it might be a link).
        unlink(target.path)
        let fd = open(target.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { throw .io(detail: "can't create \(target.lastPathComponent)") }
        defer { close(fd) }
        var block: UnsafeRawPointer?
        var size = 0
        var offset: la_int64_t = 0
        while true {
            let status = archive_read_data_block(reader, &block, &size, &offset)
            if status == ARCHIVE_EOF { return }
            guard status == ARCHIVE_OK || status == ARCHIVE_WARN else { throw dataError(reader) }
            if let block, size > 0, pwrite(fd, block, size, off_t(offset)) != size {
                throw .io(detail: "can't write \(target.lastPathComponent)")
            }
            guard progress.report(UInt64(max(0, archive_filter_bytes(reader, -1))), total) else { throw .cancelled }
        }
    }

    private func drain(_ reader: OpaquePointer, progress: ArchiveProgress, total: UInt64) throws(ArchiveError) {
        var block: UnsafeRawPointer?
        var size = 0
        var offset: la_int64_t = 0
        while true {
            let status = archive_read_data_block(reader, &block, &size, &offset)
            if status == ARCHIVE_EOF { return }
            guard status == ARCHIVE_OK || status == ARCHIVE_WARN else { throw dataError(reader) }
            guard progress.report(UInt64(max(0, archive_filter_bytes(reader, -1))), total) else { throw .cancelled }
        }
    }

    /// Restores the modification time and permission bits (never removing the owner's own
    /// read/write access).
    private func setAttributes(of target: URL, from entry: OpaquePointer) {
        var attributes: [FileAttributeKey: Any] = [:]
        if archive_entry_mtime_is_set(entry) != 0 {
            attributes[.modificationDate] = Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry)))
        }
        let permissions = Int(archive_entry_perm(entry)) & 0o777
        if permissions != 0 { attributes[.posixPermissions] = permissions | 0o600 }
        try? FileManager.default.setAttributes(attributes, ofItemAtPath: target.path)
    }

    // MARK: Writing

    public func create(_ request: PackRequest, progress: ArchiveProgress) throws(ArchiveError) -> [URL] {
        try withUTF8Locale { () throws(ArchiveError) in try createArchive(request, progress: progress) }
    }

    private func createArchive(_ request: PackRequest, progress: ArchiveProgress) throws(ArchiveError) -> [URL] {
        let items = try SourceWalker.items(for: request.sources)
        ZeigLog.info("libarchive", "create \(request.destination.lastPathComponent) (\(request.format.displayName), \(request.level.displayName)) from \(items.count) items")
        if request.format.isSingleFile, items.count != 1 || items[0].isDirectory {
            throw .invalidOptions(detail: "\(request.format.displayName) holds exactly one file")
        }
        guard let writer = archive_write_new() else { throw .other(detail: "libarchive: out of memory") }
        defer { archive_write_free(writer) }
        try configure(writer, for: request)
        guard archive_write_open_filename(writer, request.destination.path) == ARCHIVE_OK else {
            throw writeError(writer)
        }

        let total = items.reduce(UInt64(0)) { $0 + $1.size }
        var done: UInt64 = 0
        do throws(ArchiveError) {
            for item in items {
                try writeItem(item, to: writer, rawFormat: request.format.isSingleFile, progress: progress, done: &done, total: total)
            }
            guard archive_write_close(writer) == ARCHIVE_OK else { throw writeError(writer) }
        } catch {
            archive_write_close(writer)
            try? FileManager.default.removeItem(at: request.destination)
            throw error
        }
        return [request.destination]
    }

    private func configure(_ writer: OpaquePointer, for request: PackRequest) throws(ArchiveError) {
        func ok(_ status: Int32) throws(ArchiveError) {
            if status != ARCHIVE_OK && status != ARCHIVE_WARN { throw writeError(writer) }
        }
        let format = request.format
        let level = request.level

        // Container
        switch format {
        case .zip:
            try ok(archive_write_set_format_zip(writer))
            try ok(archive_write_set_format_option(writer, "zip", "compression", level == .store ? "store" : "deflate"))
            if level != .store {
                try ok(archive_write_set_format_option(writer, "zip", "compression-level", "\(level.level(in: 0...9))"))
            }
        case .sevenZip:
            try ok(archive_write_set_format_7zip(writer))
            let method = level == .store ? "store" : Self.sevenZipMethod(request.value(FormatOptions.sevenZipMethod.id))
            try ok(archive_write_set_format_option(writer, "7zip", "compression", method))
            if level != .store {
                try ok(archive_write_set_format_option(writer, "7zip", "compression-level", "\(level.level(in: 0...9))"))
            }
        case .tar:
            try ok(archive_write_set_format_pax_restricted(writer))
        case .tarGzip, .tarBzip2, .tarXz, .tarZstd, .tarLz4:
            switch request.value(FormatOptions.tarFormat.id) {
            case "gnutar": try ok(archive_write_set_format_gnutar(writer))
            case "ustar": try ok(archive_write_set_format_ustar(writer))
            default: try ok(archive_write_set_format_pax_restricted(writer))
            }
        case .iso:
            try ok(archive_write_set_format_iso9660(writer))
            let name = request.value(FormatOptions.isoVolumeName.id)
            if !name.isEmpty { try ok(archive_write_set_format_option(writer, "iso9660", "volume-id", name)) }
            // libarchive's convention: a nil value turns a boolean option off.
            try ok(archive_write_set_format_option(writer, "iso9660", "joliet",
                                                   request.isOn(FormatOptions.isoJoliet.id) ? "1" : nil))
            try ok(archive_write_set_format_option(writer, "iso9660", "rockridge",
                                                   request.isOn(FormatOptions.isoRockRidge.id) ? "1" : nil))
        case .cpio:
            try ok(archive_write_set_format_cpio_newc(writer))
        case .xar:
            try ok(archive_write_set_format_xar(writer))
        case .ar:
            try ok(archive_write_set_format_ar_bsd(writer))
        case _ where format.isSingleFile:
            try ok(archive_write_set_format_raw(writer))
        default:
            throw .readOnlyFormat
        }

        // Compressor
        let compressor = FormatDetector.compressor(of: format) ?? (format.isSingleFile ? format : nil)
        switch compressor {
        case .gzip: try ok(archive_write_add_filter_gzip(writer))
        case .bzip2: try ok(archive_write_add_filter_bzip2(writer))
        case .xz: try ok(archive_write_add_filter_xz(writer))
        case .zstd: try ok(archive_write_add_filter_zstd(writer))
        case .lz4: try ok(archive_write_add_filter_lz4(writer))
        case .lzip: try ok(archive_write_add_filter_lzip(writer))
        case .lzma: try ok(archive_write_add_filter_lzma(writer))
        case .compress: try ok(archive_write_add_filter_compress(writer))
        default: break
        }
        if let compressor, let value = Self.filterLevel(compressor, level) {
            try ok(archive_write_set_filter_option(writer, nil, "compression-level", "\(value)"))
        }

        if let password = request.effectivePassword {
            guard format == .zip || format == .sevenZip else { throw .invalidOptions(detail: "no encryption for this format") }
            if format == .sevenZip {
                // libarchive writes 7z without encryption; 7-Zip creates encrypted 7z.
                throw .invalidOptions(detail: "libarchive can't encrypt 7z")
            }
            let method = request.value(FormatOptions.zipEncryption.id) == "ZipCrypto" ? "zipcrypt" : "aes256"
            try ok(archive_write_set_format_option(writer, "zip", "encryption", method))
            try ok(archive_write_set_passphrase(writer, password))
        }
    }

    /// The filter's own level for `level`, or `nil` for filters without levels.
    static func filterLevel(_ compressor: ArchiveFormat, _ level: CompressionLevel) -> Int? {
        switch compressor {
        case .zstd:
            // zstd's scale is 1…22 with 3 as the default; past 19 needs lots of memory.
            [1, 1, 2, 3, 9, 19][level.rawValue]
        case .lz4:
            // 1 is lz4's fast default; 2…9 switch to its slower high-compression mode.
            [1, 1, 1, 1, 6, 9][level.rawValue]
        case .compress:
            nil
        default:
            // gzip, bzip2, xz, lzip, lzma: 1…9 (0 means "store" only for some of them).
            max(level.level(in: 0...9), 1)
        }
    }

    static func sevenZipMethod(_ value: String) -> String {
        switch value {
        case "LZMA": "lzma1"
        case "PPMd": "ppmd"
        case "BZip2": "bzip2"
        case "Deflate": "deflate"
        default: "lzma2"
        }
    }

    private func writeItem(
        _ item: SourceWalker.Item, to writer: OpaquePointer, rawFormat: Bool,
        progress: ArchiveProgress, done: inout UInt64, total: UInt64
    ) throws(ArchiveError) {
        guard let entry = archive_entry_new() else { throw .other(detail: "libarchive: out of memory") }
        defer { archive_entry_free(entry) }
        archive_entry_set_pathname_utf8(entry, item.nameInArchive)
        archive_entry_set_filetype(entry, item.isDirectory ? FileType.directory : FileType.regular)
        archive_entry_set_perm(entry, mode_t(item.permissions))
        archive_entry_set_size(entry, item.isDirectory ? 0 : la_int64_t(item.size))
        archive_entry_set_mtime(entry, time_t(item.modified.timeIntervalSince1970), 0)
        guard archive_write_header(writer, entry) == ARCHIVE_OK else { throw writeError(writer) }
        guard !item.isDirectory else { return }

        guard let handle = FileHandle(forReadingAtPath: item.url.path) else {
            throw .io(detail: "can't read \(item.url.lastPathComponent)")
        }
        defer { try? handle.close() }
        while true {
            let chunk: Data
            do {
                guard let data = try handle.read(upToCount: 256 * 1024), !data.isEmpty else { break }
                chunk = data
            } catch {
                throw .io(detail: "can't read \(item.url.lastPathComponent)")
            }
            let written = chunk.withUnsafeBytes { archive_write_data(writer, $0.baseAddress, $0.count) }
            guard written == chunk.count else { throw writeError(writer) }
            done += UInt64(chunk.count)
            guard progress.report(done, total) else { throw .cancelled }
        }
    }

    // MARK: Errors

    private func readError(_ reader: OpaquePointer, opening: Bool) -> ArchiveError {
        let message = archive_error_string(reader).map { String(cString: $0) } ?? "unknown libarchive error"
        ZeigLog.error("libarchive", "read: \(message) (errno \(archive_errno(reader)))")
        let lower = message.lowercased()
        if lower.contains("passphrase") || lower.contains("password") {
            return lower.contains("incorrect") || lower.contains("wrong") ? .wrongPassword : .passwordRequired
        }
        if opening, lower.contains("unrecognized archive format") { return .unsupportedFormat }
        if lower.contains("unsupported") { return .unsupportedMethod(detail: message) }
        return .corrupt(detail: message)
    }

    private func dataError(_ reader: OpaquePointer) -> ArchiveError {
        let error = readError(reader, opening: false)
        if case .passwordRequired = error { return .wrongPassword }
        return error
    }

    private func writeError(_ writer: OpaquePointer) -> ArchiveError {
        let message = archive_error_string(writer).map { String(cString: $0) } ?? "unknown libarchive error"
        ZeigLog.error("libarchive", "write: \(message) (errno \(archive_errno(writer)))")
        return archive_errno(writer) == EINVAL ? .invalidOptions(detail: message) : .io(detail: message)
    }

    private func fileSize(_ url: URL) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func createDirectory(_ url: URL) throws(ArchiveError) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw .io(detail: "can't create folder \(url.lastPathComponent)")
        }
    }
}

/// Runs `body` with this thread's character set set to UTF-8.
///
/// libarchive converts file names between the archive's encoding and "the current locale",
/// which in an app is the C locale (ASCII only) unless someone changes it, so any non-ASCII
/// name fails. `uselocale` changes it for the calling thread only, leaving the rest of the
/// app alone, and the old locale is restored afterwards.
private func withUTF8Locale<T>(_ body: () throws(ArchiveError) -> T) throws(ArchiveError) -> T {
    let previous = uselocale(utf8Locale)
    defer { uselocale(previous) }
    return try body()
}

// nonisolated(unsafe): locale_t is a C pointer Swift can't mark Sendable. It's created once
// and never mutated, and uselocale may be called with it from any thread.
private nonisolated(unsafe) let utf8Locale: locale_t? = newlocale(LC_CTYPE_MASK, "UTF-8", nil)

/// libarchive's file type constants (AE_IFREG …). Its header defines them as macros with
/// casts, which Swift doesn't import.
private enum FileType {
    static let regular: UInt32 = 0o100000
    static let directory: UInt32 = 0o040000
    static let symlink: UInt32 = 0o120000
}
