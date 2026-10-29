import Foundation

/// The three archive engines.
public enum BackendID: String, Sendable, Codable, CaseIterable, Identifiable {
    /// 7-Zip: the main backend.
    case sevenZip
    /// libarchive: formats 7-Zip lacks, or can only read where libarchive also writes.
    case libArchive
    /// rars: experimental, RAR only, opt-in (Settings → Experimental).
    case rars

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sevenZip: "7-Zip"
        case .libArchive: "libarchive"
        case .rars: "rars"
        }
    }
}

/// One file or folder inside an archive.
public struct ArchiveEntry: Sendable, Hashable, Identifiable {
    /// The backend's index for the entry; pass it back to extract just this entry.
    public var index: Int
    /// Path inside the archive with "/" separators, as stored. Use `sanitizedPath` for disk.
    public var path: String
    public var size: UInt64
    /// Compressed size, or `nil` where the format doesn't record it per entry.
    public var packedSize: UInt64?
    public var modified: Date?
    public var isDirectory: Bool
    public var isEncrypted: Bool
    public var isSymlink: Bool

    public var id: Int { index }

    public init(
        index: Int, path: String, size: UInt64, packedSize: UInt64? = nil, modified: Date? = nil,
        isDirectory: Bool = false, isEncrypted: Bool = false, isSymlink: Bool = false
    ) {
        self.index = index
        self.path = path
        self.size = size
        self.packedSize = packedSize
        self.modified = modified
        self.isDirectory = isDirectory
        self.isEncrypted = isEncrypted
        self.isSymlink = isSymlink
    }

    /// Last path component.
    public var name: String { path.split(separator: "/").last.map(String.init) ?? path }

    /// The path with "", "." and ".." components and leading "/" removed, so it always
    /// stays inside an extraction folder. `nil` when nothing is left.
    public var sanitizedPath: String? { ArchiveEntry.sanitize(path) }

    public static func sanitize(_ path: String) -> String? {
        let parts = path.split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .filter { $0 != "." && $0 != ".." }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }
}

/// What an engine knows about an archive as a whole. Every field is optional: each engine
/// reports what its format and API expose.
public struct ArchiveInfo: Sendable, Equatable {
    /// The engine's own name for the format ("7z", "Rar5", "POSIX pax interchange format").
    public var formatName: String?
    /// Compression method(s), such as "LZMA2:24 BCJ" or "gzip".
    public var method: String?
    public var isSolid: Bool?
    /// Bytes the archive takes on disk (all volumes), when the engine knows it.
    public var physicalSize: UInt64?
    public var volumeCount: Int?
    public var comment: String?

    public init(
        formatName: String? = nil, method: String? = nil, isSolid: Bool? = nil,
        physicalSize: UInt64? = nil, volumeCount: Int? = nil, comment: String? = nil
    ) {
        self.formatName = formatName
        self.method = method
        self.isSolid = isSolid
        self.physicalSize = physicalSize
        self.volumeCount = volumeCount
        self.comment = comment
    }
}

/// What listing an archive returns: its entries and what's known about the whole.
public struct ArchiveContents: Sendable {
    public var entries: [ArchiveEntry]
    public var info: ArchiveInfo

    public init(entries: [ArchiveEntry], info: ArchiveInfo = ArchiveInfo()) {
        self.entries = entries
        self.info = info
    }
}

/// What opening an archive found.
public struct ArchiveListing: Sendable {
    public var url: URL
    /// The detected format, if Zeig names it.
    public var format: ArchiveFormat?
    public var backend: BackendID
    public var entries: [ArchiveEntry]
    public var info: ArchiveInfo
    /// `true` when the router's first choice couldn't open the file and another backend did.
    public var usedFallback: Bool

    public init(
        url: URL, format: ArchiveFormat?, backend: BackendID, entries: [ArchiveEntry],
        info: ArchiveInfo = ArchiveInfo(), usedFallback: Bool = false
    ) {
        self.url = url
        self.format = format
        self.backend = backend
        self.entries = entries
        self.info = info
        self.usedFallback = usedFallback
    }

    /// Numbers for the Info sheet, worked out from the entries and the file on disk.
    public var statistics: ArchiveStatistics {
        ArchiveStatistics(entries: entries, archiveSize: info.physicalSize ?? Self.fileSize(url))
    }

    private static func fileSize(_ url: URL) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }
}

/// Counts and sizes of an archive's contents.
public struct ArchiveStatistics: Sendable, Equatable {
    public var fileCount: Int
    /// Folders stored in the archive plus folders only implied by paths.
    public var folderCount: Int
    public var encryptedCount: Int
    /// Total size of the files when extracted.
    public var originalSize: UInt64
    /// Size of the archive file(s).
    public var archiveSize: UInt64
    public var newest: Date?
    public var oldest: Date?

    public init(entries: [ArchiveEntry], archiveSize: UInt64) {
        let files = entries.filter { !$0.isDirectory }
        fileCount = files.count
        var folders = Set(entries.filter(\.isDirectory).compactMap(\.sanitizedPath))
        for file in files {
            guard let path = file.sanitizedPath else { continue }
            var parts = path.split(separator: "/").dropLast()
            while !parts.isEmpty {
                folders.insert(parts.joined(separator: "/"))
                parts = parts.dropLast()
            }
        }
        folderCount = folders.count
        encryptedCount = files.filter(\.isEncrypted).count
        originalSize = files.reduce(0) { $0 + $1.size }
        self.archiveSize = archiveSize
        let dates = entries.compactMap(\.modified)
        newest = dates.max()
        oldest = dates.min()
    }

    /// Archive size as a fraction of the original (0.3 = the archive is 30% of the original),
    /// or `nil` for an empty archive.
    public var ratio: Double? {
        originalSize > 0 ? Double(archiveSize) / Double(originalSize) : nil
    }

    /// How much smaller the archive is than its contents, 0…1 (negative if it grew).
    public var savings: Double? { ratio.map { 1 - $0 } }
}

/// Why an archive operation failed. Every backend maps its own errors to these.
public enum ArchiveError: Error, Sendable, Equatable {
    case unsupportedFormat
    case passwordRequired
    case wrongPassword
    /// Headers or data are damaged. `detail` is the backend's English message.
    case corrupt(detail: String)
    case unsupportedMethod(detail: String)
    case io(detail: String)
    case cancelled
    case invalidOptions(detail: String)
    /// The format can't be created (by any enabled backend).
    case readOnlyFormat
    case other(detail: String)

    /// Short sentence for alerts.
    public var message: String {
        switch self {
        case .unsupportedFormat: "This file isn't an archive Zeig can open."
        case .passwordRequired: "This archive is protected with a password."
        case .wrongPassword: "The password is wrong."
        case .corrupt: "The archive is damaged."
        case .unsupportedMethod: "The archive uses a compression method Zeig doesn't support."
        case .io: "A file couldn't be read or written."
        case .cancelled: "Cancelled."
        case .invalidOptions: "These settings don't work for this format."
        case .readOnlyFormat: "Zeig can open this format but not create it."
        case .other: "Something went wrong."
        }
    }

    /// Backend detail for "Show details", if any.
    public var detail: String? {
        switch self {
        case .corrupt(let d), .unsupportedMethod(let d), .io(let d), .invalidOptions(let d), .other(let d): d
        default: nil
        }
    }

    /// Worth trying another backend: the first one may simply not understand the file.
    public var allowsFallback: Bool {
        switch self {
        case .unsupportedFormat, .corrupt, .unsupportedMethod: true
        default: false
        }
    }
}

/// Progress for a long operation. Called on the operation's thread; return `false` to cancel.
public struct ArchiveProgress: Sendable {
    public let report: @Sendable (_ completed: UInt64, _ total: UInt64) -> Bool

    public init(_ report: @escaping @Sendable (_ completed: UInt64, _ total: UInt64) -> Bool) {
        self.report = report
    }

    public static let none = ArchiveProgress { _, _ in true }
}

/// What every backend can do. Implementations block; call them off the main actor
/// (`ArchiveService` does).
public protocol ArchiveBackend: Sendable {
    var id: BackendID { get }
    /// The engine's version, for Settings → Backends.
    var version: String { get }

    func list(_ archive: URL, format: ArchiveFormat?, password: String?) throws(ArchiveError) -> ArchiveContents

    /// Extracts `entries` (all when `nil`) into the existing folder `destination`.
    func extract(
        _ archive: URL, format: ArchiveFormat?, to destination: URL, entries: [ArchiveEntry]?,
        password: String?, progress: ArchiveProgress
    ) throws(ArchiveError)

    /// Decompresses everything and checks it, writing nothing.
    func test(_ archive: URL, format: ArchiveFormat?, password: String?, progress: ArchiveProgress) throws(ArchiveError)

    /// Writes a new archive; returns the files written (several for split archives).
    func create(_ request: PackRequest, progress: ArchiveProgress) throws(ArchiveError) -> [URL]
}
