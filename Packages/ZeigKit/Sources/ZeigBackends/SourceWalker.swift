import Foundation
import ZeigCore

/// Lists the files and folders to add to a new archive, the same way for every backend
/// that needs it (libarchive; 7-Zip and rars walk folders themselves): each source is named
/// after itself, folders bring everything inside in name order, symbolic links are left out.
enum SourceWalker {
    struct Item: Equatable {
        var url: URL
        var nameInArchive: String
        var isDirectory: Bool
        var size: UInt64
        var modified: Date
        var permissions: Int
    }

    static func items(for sources: [URL]) throws(ArchiveError) -> [Item] {
        var items: [Item] = []
        for source in sources {
            try collect(source, name: source.lastPathComponent, into: &items)
        }
        return items
    }

    private static func collect(_ url: URL, name: String, into items: inout [Item]) throws(ArchiveError) {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw .io(detail: "can't read \(url.lastPathComponent)")
        }
        let type = attributes[.type] as? FileAttributeType
        guard type != .typeSymbolicLink else { return }
        let isDirectory = type == .typeDirectory
        items.append(Item(
            url: url,
            nameInArchive: name,
            isDirectory: isDirectory,
            size: isDirectory ? 0 : (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            modified: attributes[.modificationDate] as? Date ?? .now,
            permissions: (attributes[.posixPermissions] as? NSNumber)?.intValue ?? (isDirectory ? 0o755 : 0o644)
        ))
        guard isDirectory else { return }
        let children: [String]
        do {
            children = try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
        } catch {
            throw .io(detail: "can't list \(url.lastPathComponent)")
        }
        for child in children {
            try collect(url.appendingPathComponent(child), name: name + "/" + child, into: &items)
        }
    }
}
