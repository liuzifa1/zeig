import Foundation
import ZeigCore

/// What takes space in the app's folder, for Settings › Storage: totals by kind, the largest
/// files, and archives that were already extracted next to themselves (the archive can go,
/// the folder keeps the contents).
///
/// `scan` reads the disk and blocks, so call it off the main actor. Sizes are the files'
/// lengths, the same numbers the file lists show. Hidden files are skipped, as in the lists.
public struct StorageReport: Sendable {
    /// A file or folder, with a folder's size being everything in it.
    public struct Entry: Identifiable, Hashable, Sendable {
        public var url: URL
        /// Path relative to the scanned folder ("Photos/trip.zip"), like `FileItem.relativePath`.
        public var relativePath: String
        public var size: UInt64
        public var isDirectory: Bool
        public var modified: Date

        public var id: String { relativePath }
        public var name: String { url.lastPathComponent }
    }

    /// An archive and the folders it was extracted into ("photos.zip" and "photos", or
    /// "photos 2", … when it was extracted again), by name.
    public struct Extracted: Identifiable, Hashable, Sendable {
        public var archive: Entry
        public var folders: [Entry]
        public var id: String { archive.id }
        public var foldersSize: UInt64 { folders.reduce(0) { $0.addingSaturating($1.size) } }
    }

    /// Where every byte goes. The three add up to `total`.
    public enum Kind: CaseIterable, Sendable {
        /// Archive files, except those inside extracted folders.
        case archives
        /// Everything inside folders that hold an archive's extracted contents.
        case extracted
        /// Everything else.
        case other
    }

    public var total: UInt64 = 0
    public var sizes: [Kind: UInt64] = [:]
    /// Files anywhere in the folder, largest first, at most `largestLimit`.
    public var largestFiles: [Entry] = []
    /// Archives whose extracted folder is next to them, largest archive first.
    public var extracted: [Extracted] = []

    public func size(of kind: Kind) -> UInt64 { sizes[kind] ?? 0 }

    public init() {}

    /// Reads everything under `root`.
    public static func scan(_ root: URL, largestLimit: Int = 100, fileManager: FileManager = .default) -> StorageReport {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        func relative(_ url: URL) -> String {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            return path.hasPrefix(base)
                ? String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : url.lastPathComponent
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        var files: [Entry] = []
        var folders: [String: Entry] = [:]
        let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let entry = Entry(
                url: url, relativePath: relative(url), size: UInt64(values.fileSize ?? 0),
                isDirectory: values.isDirectory ?? false, modified: values.contentModificationDate ?? .distantPast
            )
            if entry.isDirectory { folders[entry.relativePath] = entry } else { files.append(entry) }
        }

        // Folder sizes: every file counts toward each folder above it. Saturating, like every
        // sum here: sizes come from the file system, but a sparse file can claim anything.
        for file in files {
            var path = (file.relativePath as NSString).deletingLastPathComponent
            while !path.isEmpty {
                if let folder = folders[path] { folders[path]?.size = folder.size.addingSaturating(file.size) }
                path = (path as NSString).deletingLastPathComponent
            }
        }

        var report = StorageReport()
        let archives = files.filter { FormatDetector.format(forName: $0.name) != nil }
        for archive in archives {
            let parent = (archive.relativePath as NSString).deletingLastPathComponent
            let stem = FileNaming.extractionFolder(for: archive.url).lastPathComponent
            let matches = folders.values
                .filter { ($0.relativePath as NSString).deletingLastPathComponent == parent && isExtractionName($0.name, stem: stem) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if !matches.isEmpty { report.extracted.append(Extracted(archive: archive, folders: matches)) }
        }
        report.extracted.sort { ($0.archive.size, $0.id) > ($1.archive.size, $1.id) }

        let extractedFolders = Set(report.extracted.flatMap(\.folders).map(\.relativePath))
        func isInExtractedFolder(_ file: Entry) -> Bool {
            var path = (file.relativePath as NSString).deletingLastPathComponent
            while !path.isEmpty {
                if extractedFolders.contains(path) { return true }
                path = (path as NSString).deletingLastPathComponent
            }
            return false
        }
        for file in files {
            let kind: Kind = isInExtractedFolder(file) ? .extracted
                : FormatDetector.format(forName: file.name) != nil ? .archives : .other
            report.sizes[kind, default: 0] = report.sizes[kind, default: 0].addingSaturating(file.size)
            report.total = report.total.addingSaturating(file.size)
        }
        report.largestFiles = Array(files.sorted { ($0.size, $0.id) > ($1.size, $1.id) }.prefix(largestLimit))
        return report
    }

    /// "photos" or "photos 2", "photos 3", …: the names `FileNaming.unique` gives an
    /// extraction folder.
    static func isExtractionName(_ name: String, stem: String) -> Bool {
        if name.compare(stem, options: .caseInsensitive) == .orderedSame { return true }
        guard name.count > stem.count + 1,
              name.prefix(stem.count).compare(stem, options: .caseInsensitive) == .orderedSame else { return false }
        let rest = name.dropFirst(stem.count)
        return rest.first == " " && rest.dropFirst().allSatisfy(\.isNumber) && rest.count > 1
    }

    /// Everything under `folder`, in bytes (temporary files).
    public static func size(of folder: URL, fileManager: FileManager = .default) -> UInt64 {
        var size: UInt64 = 0
        let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        while let url = enumerator?.nextObject() as? URL {
            size = size.addingSaturating(UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
        }
        return size
    }
}
