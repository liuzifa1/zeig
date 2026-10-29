import Foundation
import Observation
import ZeigCore

/// A file or folder in the app's folder.
public struct FileItem: Identifiable, Hashable, Sendable {
    public var url: URL
    /// Path relative to the library root ("Photos/trip.zip"); stable ID for lists and Recent.
    public var relativePath: String
    public var isDirectory: Bool
    public var size: UInt64
    public var modified: Date
    /// The archive format the name or contents suggest, if any.
    public var format: ArchiveFormat?

    public var id: String { relativePath }
    public var name: String { url.lastPathComponent }
    public var isArchive: Bool { !isDirectory && format != nil }
}

/// The app's own folder (Documents, shown in Files as On My iPhone › Zeig) and everything
/// Zeig does to files in it.
///
/// Zeig only works inside this folder: files from elsewhere are copied in first
/// (`importFiles`), and archives always extract next to themselves. So nothing else needs
/// security-scoped access, and Recent can always reopen what it lists. On APFS a copy from
/// the same volume is a clone and takes no extra space until one side changes.
///
/// Views observe `changeCount`, which goes up after every change made through the library.
@MainActor
@Observable
public final class FileLibrary {
    public let root: URL
    public private(set) var changeCount = 0
    private let fileManager = FileManager.default

    public init(root: URL) {
        self.root = root.standardizedFileURL
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// The app's Documents folder.
    public static func documents() -> FileLibrary {
        FileLibrary(root: URL.documentsDirectory)
    }

    /// Call after something outside the library changed files (an extraction finished).
    public func noteChange() { changeCount += 1 }

    // MARK: Reading

    /// The items directly in `folder` (the root when `nil`): folders first, then by name.
    public func contents(of folder: URL? = nil) -> [FileItem] {
        let folder = folder ?? root
        let urls = (try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Self.keys, options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap(item(for:)).sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Every file and folder in the library, for search.
    public func allItems() -> [FileItem] {
        let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: Self.keys, options: [.skipsHiddenFiles])
        var items: [FileItem] = []
        while let url = enumerator?.nextObject() as? URL {
            if let item = item(for: url) { items.append(item) }
        }
        return items
    }

    public func item(for url: URL) -> FileItem? {
        guard let values = try? url.resourceValues(forKeys: Set(Self.keys)) else { return nil }
        let isDirectory = values.isDirectory ?? false
        return FileItem(
            url: url,
            relativePath: relativePath(of: url),
            isDirectory: isDirectory,
            size: UInt64(values.fileSize ?? 0),
            modified: values.contentModificationDate ?? .distantPast,
            format: isDirectory ? nil : FormatDetector.format(forName: url.lastPathComponent)
        )
    }

    public func item(atRelativePath path: String) -> FileItem? {
        let url = root.appendingPathComponent(path)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return item(for: url)
    }

    public func relativePath(of url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let base = root.resolvingSymlinksInPath().path
        guard path.hasPrefix(base) else { return url.lastPathComponent }
        return String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: Changing

    /// Copies files from outside the app (a document picker, "Open in Zeig") into `folder`.
    /// Returns the copies. Names that already exist get " 2", " 3", ….
    @discardableResult
    public func importFiles(_ urls: [URL], into folder: URL? = nil) throws -> [URL] {
        let folder = folder ?? root
        var copies: [URL] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let target = FileNaming.unique(folder.appendingPathComponent(url.lastPathComponent))
            // Coordinated, so files from iCloud Drive and other providers are downloaded first.
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: .forUploading, error: &coordinationError) { readable in
                do { try self.fileManager.copyItem(at: readable, to: target) } catch { copyError = error }
            }
            if let error = coordinationError ?? copyError { throw error }
            copies.append(target)
        }
        changeCount += 1
        return copies
    }

    /// A file another app sent with "Open in Zeig". iOS puts such files in Documents/Inbox
    /// first (Zeig doesn't open documents in place); those are moved to the top of the
    /// library and the Inbox folder removed once empty. Anything else is copied in.
    public func adoptOpenedFile(_ url: URL) throws -> URL {
        guard isInside(url) else { return try importFiles([url])[0] }
        let target = FileNaming.unique(root.appendingPathComponent(url.lastPathComponent))
        try fileManager.moveItem(at: url, to: target)
        let inbox = root.appendingPathComponent("Inbox")
        if (try? fileManager.contentsOfDirectory(atPath: inbox.path))?.isEmpty == true {
            try? fileManager.removeItem(at: inbox)
        }
        changeCount += 1
        return target
    }

    @discardableResult
    public func createFolder(named name: String, in folder: URL? = nil) throws -> URL {
        let url = FileNaming.unique((folder ?? root).appendingPathComponent(Self.safeName(name, fallback: "New Folder")))
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        changeCount += 1
        return url
    }

    @discardableResult
    public func rename(_ url: URL, to name: String) throws -> URL {
        let target = url.deletingLastPathComponent().appendingPathComponent(Self.safeName(name, fallback: url.lastPathComponent))
        guard target != url else { return url }
        let unique = FileNaming.unique(target)
        try fileManager.moveItem(at: url, to: unique)
        changeCount += 1
        return unique
    }

    public func delete(_ urls: [URL]) throws {
        for url in urls where isInside(url) {
            try fileManager.removeItem(at: url)
        }
        changeCount += 1
    }

    /// Copies each item next to itself as "name copy.ext" ("name copy 2.ext", … if taken),
    /// like the Files app's Duplicate. Returns the copies.
    @discardableResult
    public func duplicate(_ urls: [URL]) throws -> [URL] {
        var copies: [URL] = []
        for url in urls where isInside(url) {
            let (stem, ext) = FileNaming.split(url.lastPathComponent)
            let name = stem + " copy" + (ext.isEmpty ? "" : "." + ext)
            let target = FileNaming.unique(url.deletingLastPathComponent().appendingPathComponent(name))
            try fileManager.copyItem(at: url, to: target)
            copies.append(target)
        }
        changeCount += 1
        return copies
    }

    /// Makes a new folder next to the first item and moves the items into it (Files' "New
    /// Folder with Items"). Returns the folder.
    @discardableResult
    public func newFolder(containing urls: [URL], named name: String = "New Folder") throws -> URL {
        guard let first = urls.first else { return try createFolder(named: name) }
        let folder = try createFolder(named: name, in: first.deletingLastPathComponent())
        try move(urls, into: folder)
        return folder
    }

    /// Every folder in the library, root first, then depth-first by name; for the Move picker.
    public func allFolders() -> [FileItem] {
        func walk(_ folder: URL?) -> [FileItem] {
            contents(of: folder).filter(\.isDirectory).flatMap { [$0] + walk($0.url) }
        }
        return walk(nil)
    }

    /// Moves items into `folder` (inside the library).
    public func move(_ urls: [URL], into folder: URL) throws {
        for url in urls where isInside(url) && url != folder && !folder.path.hasPrefix(url.path + "/") {
            // Already there: nothing to do (and moving would rename it "name 2").
            guard url.deletingLastPathComponent().standardizedFileURL.path != folder.standardizedFileURL.path else { continue }
            try fileManager.moveItem(at: url, to: FileNaming.unique(folder.appendingPathComponent(url.lastPathComponent)))
        }
        changeCount += 1
    }

    public func isInside(_ url: URL) -> Bool {
        url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/")
    }

    /// `name` without path separators and leading dots, or `fallback` if nothing is left.
    static func safeName(_ name: String, fallback: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = String(cleaned.drop { $0 == "." })
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
}
