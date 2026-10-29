import Foundation

/// An archive's flat entry list as folders, for browsing.
///
/// Many archives don't store folder entries ("a/b/c.txt" with no "a/" or "a/b/"), so folders
/// are made up from the paths. Paths are sanitized first (so "../x" shows as "x", the same
/// place extraction will put it).
public struct ArchiveTree: Sendable {
    public struct Node: Identifiable, Hashable, Sendable {
        /// Full sanitized path inside the archive; also the ID.
        public var path: String
        public var name: String
        public var isDirectory: Bool
        /// The entry itself (files, and folders the archive stores explicitly).
        public var entry: ArchiveEntry?
        /// For folders: total size and every entry inside, for extracting the folder.
        public var size: UInt64
        public var id: String { path }
    }

    private var children: [String: [Node]] = [:]
    private var entriesUnder: [String: [ArchiveEntry]] = [:]

    public init(entries: [ArchiveEntry]) {
        var folders: [String: (size: UInt64, entry: ArchiveEntry?)] = [:]
        var files: [String: [Node]] = [:]
        for entry in entries {
            guard let path = entry.sanitizedPath else { continue }
            let parts = path.split(separator: "/").map(String.init)
            // Every ancestor is a folder, stored or not.
            for depth in 0..<parts.count {
                let ancestor = parts[0..<depth].joined(separator: "/")
                entriesUnder[ancestor, default: []].append(entry)
                if depth > 0 {
                    folders[ancestor, default: (0, nil)].size += entry.isDirectory ? 0 : entry.size
                }
            }
            if entry.isDirectory {
                folders[path, default: (0, nil)].entry = entry
                entriesUnder[path, default: []].append(entry)
            } else {
                let parent = parts.dropLast().joined(separator: "/")
                files[parent, default: []].append(Node(path: path, name: parts.last!, isDirectory: false, entry: entry, size: entry.size))
            }
        }
        for (path, info) in folders {
            let parts = path.split(separator: "/")
            let parent = parts.dropLast().joined(separator: "/")
            children[parent, default: []].append(Node(path: path, name: String(parts.last!), isDirectory: true, entry: info.entry, size: info.size))
        }
        for (parent, nodes) in files { children[parent, default: []] += nodes }
        for key in children.keys {
            children[key]?.sort { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    /// What's directly inside the folder at `path` ("" for the top).
    public func children(of path: String) -> [Node] { children[path] ?? [] }

    /// Every entry at or below `node`, for extracting it.
    public func entries(for node: Node) -> [ArchiveEntry] {
        node.isDirectory ? entriesUnder[node.path] ?? [] : node.entry.map { [$0] } ?? []
    }
}
