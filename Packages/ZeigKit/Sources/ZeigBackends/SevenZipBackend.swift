import CSevenZip
import Foundation
import ZeigCore

/// 7-Zip, through the C bridge in Native/zeig7z (imported as `CSevenZip`).
///
/// The main backend: it opens nearly everything and creates zip, 7z, tar, gzip, bzip2, xz
/// and wim. Calls block; `ArchiveService` runs them off the main actor.
public struct SevenZipBackend: ArchiveBackend {
    public let id = BackendID.sevenZip

    public init() {}

    public var version: String { String(cString: zeig7z_version()) }

    /// One handler compiled into the 7-Zip library.
    public struct Handler: Sendable, Hashable {
        public var name: String
        public var extensions: [String]
        public var canWrite: Bool
    }

    /// Every format handler in the library, as 7-Zip names them.
    public static var handlers: [Handler] {
        (0..<zeig7z_format_count()).compactMap { index in
            var info = zeig7z_format_info()
            guard zeig7z_format_at(index, &info) == ZEIG7Z_OK else { return nil }
            return Handler(
                name: String(cString: info.name),
                extensions: String(cString: info.extensions).split(separator: " ").map(String.init),
                canWrite: info.can_write != 0
            )
        }
    }

    /// The 7-Zip handlers to try for `format`, comma-separated; `nil` lets 7-Zip detect it.
    static func handlerNames(for format: ArchiveFormat?) -> String? {
        switch format {
        case .zip: "zip"
        case .sevenZip: "7z"
        case .rar: "Rar5,Rar"
        case .tar: "tar"
        case .gzip: "gzip"
        case .bzip2: "bzip2"
        case .xz: "xz"
        case .zstd: "zstd"
        case .lzma: "lzma"
        case .compress: "Z"
        case .wim: "wim"
        case .iso: "Iso,Udf"
        case .cpio: "Cpio"
        case .xar: "Xar"
        case .ar, .deb: "Ar"
        case .cab: "Cab"
        case .dmg: "Dmg"
        case .lzh: "Lzh"
        case .arj: "Arj"
        case .chm: "Chm"
        case .rpm: "Rpm"
        case .msi: "Compound"
        case .squashfs: "SquashFS"
        case .vhd: "VHD,VHDX"
        case .vmdk: "VMDK"
        // Compressed tars, lz4, lzip: not 7-Zip's (see BackendCapabilities); let it try anyway.
        default: nil
        }
    }

    // MARK: Reading

    public func list(_ archive: URL, format: ArchiveFormat?, password: String?) throws(ArchiveError) -> ArchiveContents {
        try withArchive(archive, format: format, password: password) { handle in
            let entries: [ArchiveEntry] = (0..<zeig7z_entry_count(handle)).compactMap { index in
                var entry = zeig7z_entry()
                guard zeig7z_entry_at(handle, index, &entry) == ZEIG7Z_OK else { return nil }
                return ArchiveEntry(
                    index: Int(index),
                    path: String(cString: entry.path),
                    size: entry.size,
                    packedSize: entry.packed_size > 0 ? entry.packed_size : nil,
                    modified: entry.has_modified != 0 ? Date(timeIntervalSince1970: TimeInterval(entry.modified)) : nil,
                    isDirectory: entry.is_directory != 0,
                    isEncrypted: entry.is_encrypted != 0,
                    isSymlink: entry.is_symlink != 0
                )
            }
            var details = zeig7z_archive_info()
            var info = ArchiveInfo(formatName: String(cString: zeig7z_archive_format(handle)))
            if zeig7z_get_archive_info(handle, &details) == ZEIG7Z_OK {
                let method = String(cString: details.method)
                let comment = String(cString: details.comment)
                info.method = method.isEmpty ? nil : method
                info.isSolid = details.solid < 0 ? nil : details.solid == 1
                info.physicalSize = details.physical_size > 0 ? details.physical_size : nil
                info.volumeCount = details.volume_count > 0 ? Int(details.volume_count) : nil
                info.comment = comment.isEmpty ? nil : comment
            }
            ZeigLog.debug("7-Zip", "\(archive.lastPathComponent): \(info.formatName ?? "?"), \(entries.count) entries, method \(info.method ?? "?")")
            return ArchiveContents(entries: entries, info: info)
        }
    }

    public func extract(
        _ archive: URL, format: ArchiveFormat?, to destination: URL, entries: [ArchiveEntry]?,
        password: String?, progress: ArchiveProgress
    ) throws(ArchiveError) {
        try withArchive(archive, format: format, password: password) { (handle) throws(ArchiveError) in
            let indices = entries.map { $0.map { UInt32($0.index) }.sorted() }
            let result = withCallbacks(progress) { callbacks in
                if let indices {
                    indices.withUnsafeBufferPointer { buffer in
                        zeig7z_extract(handle, destination.path, buffer.baseAddress, UInt32(buffer.count), password, callbacks)
                    }
                } else {
                    zeig7z_extract(handle, destination.path, nil, 0, password, callbacks)
                }
            }
            try check(result)
        }
    }

    public func test(_ archive: URL, format: ArchiveFormat?, password: String?, progress: ArchiveProgress) throws(ArchiveError) {
        try withArchive(archive, format: format, password: password) { (handle) throws(ArchiveError) in
            try check(withCallbacks(progress) { zeig7z_test(handle, password, $0) })
        }
    }

    // MARK: Writing

    public func create(_ request: PackRequest, progress: ArchiveProgress) throws(ArchiveError) -> [URL] {
        guard let handler = Self.handlerNames(for: request.format), !handler.contains(",") else {
            throw .readOnlyFormat
        }
        let properties = Self.properties(for: request)
        ZeigLog.info("7-Zip", "create \(request.destination.lastPathComponent) as \(handler), -m \(properties.map { "\($0.0)=\($0.1)" }.joined(separator: " "))\(request.effectivePassword != nil ? ", encrypted" : "")")
        let sources = request.sources.map(\.path)
        let password = request.effectivePassword
        let result = withCStrings(sources) { sourcePointers in
            withProperties(properties) { propertyPointers in
                withCallbacks(progress) { callbacks in
                    zeig7z_create(
                        request.destination.path, handler,
                        sourcePointers.baseAddress, sourcePointers.count,
                        propertyPointers.baseAddress, propertyPointers.count,
                        password, callbacks
                    )
                }
            }
        }
        try check(result)
        return [request.destination]
    }

    /// The -m switches for a request, as (key, value) pairs. Exposed for tests.
    static func properties(for request: PackRequest) -> [(String, String)] {
        let level = request.level.level(in: 0...9)
        let stored = request.level == .store
        switch request.format {
        case .sevenZip:
            var properties = [("x", "\(level)")]
            if !stored {
                properties.append(("m", request.value(FormatOptions.sevenZipMethod.id)))
                let dictionary = request.value(FormatOptions.dictionary.id)
                if dictionary != "auto" { properties.append(("d", dictionary)) }
            }
            properties.append(("s", request.isOn(FormatOptions.solid.id) ? "on" : "off"))
            if request.effectivePassword != nil, request.isOn(FormatOptions.encryptNames.id) {
                properties.append(("he", "on"))
            }
            return properties
        case .zip:
            var properties = [("x", "\(level)")]
            if !stored { properties.append(("m", request.value(FormatOptions.zipMethod.id))) }
            if request.effectivePassword != nil {
                properties.append(("em", request.value(FormatOptions.zipEncryption.id)))
            }
            return properties
        case .gzip, .bzip2, .xz:
            // These have no "store"; 1 is their lightest setting.
            return [("x", "\(max(level, 1))")]
        default:
            // tar and wim take no level.
            return []
        }
    }
}

// MARK: - C plumbing

/// Keeps the Swift progress closure alive while C holds a pointer to it.
private final class ProgressBox {
    let reporter: ArchiveProgress
    init(_ reporter: ArchiveProgress) { self.reporter = reporter }
}

private func withCallbacks<T>(_ progress: ArchiveProgress, _ body: (UnsafePointer<zeig7z_callbacks>) -> T) -> T {
    let box = Unmanaged.passRetained(ProgressBox(progress))
    defer { box.release() }
    var callbacks = zeig7z_callbacks(
        context: box.toOpaque(),
        progress: { context, completed, total in
            guard let context else { return 0 }
            let box = Unmanaged<ProgressBox>.fromOpaque(context).takeUnretainedValue()
            return box.reporter.report(completed, total) ? 0 : 1
        }
    )
    return withUnsafePointer(to: &callbacks, body)
}

/// Opens, runs `body`, and always closes.
private func withArchive<T>(
    _ url: URL, format: ArchiveFormat?, password: String?,
    _ body: (OpaquePointer) throws(ArchiveError) -> T
) throws(ArchiveError) -> T {
    var handle: OpaquePointer?
    try check(zeig7z_open(url.path, SevenZipBackend.handlerNames(for: format), password, &handle))
    guard let handle else { throw .other(detail: "7-Zip returned no archive") }
    defer { zeig7z_close(handle) }
    return try body(handle)
}

private func check(_ result: zeig7z_result) throws(ArchiveError) {
    guard result != ZEIG7Z_OK else { return }
    let detail = String(cString: zeig7z_last_error())
    ZeigLog.log(result == ZEIG7Z_CANCELLED ? .info : .error, "7-Zip", "result \(result.rawValue): \(detail)")
    switch result {
    case ZEIG7Z_UNSUPPORTED_FORMAT: throw .unsupportedFormat
    case ZEIG7Z_CORRUPT_ARCHIVE: throw .corrupt(detail: detail)
    case ZEIG7Z_WRONG_PASSWORD:
        throw detail.contains("needs a password") ? .passwordRequired : .wrongPassword
    case ZEIG7Z_DATA_ERROR: throw .corrupt(detail: detail)
    case ZEIG7Z_UNSUPPORTED_METHOD: throw .unsupportedMethod(detail: detail)
    case ZEIG7Z_IO_ERROR: throw .io(detail: detail)
    case ZEIG7Z_CANCELLED: throw .cancelled
    case ZEIG7Z_INVALID_ARGUMENT: throw .invalidOptions(detail: detail)
    case ZEIG7Z_READ_ONLY_FORMAT: throw .readOnlyFormat
    default: throw .other(detail: detail)
    }
}

/// A C array of C strings, valid inside `body`.
private func withCStrings<T>(_ strings: [String], _ body: (UnsafeBufferPointer<UnsafePointer<CChar>?>) -> T) -> T {
    let duplicates = strings.map { strdup($0) }
    defer { duplicates.forEach { free($0) } }
    let pointers = duplicates.map { UnsafePointer($0) }
    return pointers.withUnsafeBufferPointer(body)
}

private func withProperties<T>(_ pairs: [(String, String)], _ body: (UnsafeBufferPointer<zeig7z_property>) -> T) -> T {
    let keys = pairs.map { strdup($0.0) }
    let values = pairs.map { strdup($0.1) }
    defer { (keys + values).forEach { free($0) } }
    let properties = zip(keys, values).map { zeig7z_property(key: $0, value: $1) }
    return properties.withUnsafeBufferPointer(body)
}
