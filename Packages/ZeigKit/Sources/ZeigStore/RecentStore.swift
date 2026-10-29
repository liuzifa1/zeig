import Foundation
import Observation

/// Something Zeig did with a file, for the Recent tab.
public struct RecentEntry: Codable, Hashable, Identifiable, Sendable {
    public enum Action: String, Codable, Sendable {
        case opened, created, extracted, imported

        public var label: String {
            switch self {
            case .opened: "Opened"
            case .created: "Created"
            case .extracted: "Extracted"
            case .imported: "Imported"
            }
        }
    }

    /// Path relative to the library root, so the list survives the app's container moving
    /// (which iOS does on updates).
    public var relativePath: String
    public var action: Action
    public var date: Date

    public var id: String { relativePath }
}

/// Recently opened, created, extracted and imported files: the newest action per file, newest
/// first, at most `limit`. Saved as JSON in Application Support (not in the library folder,
/// so it never shows up in Files).
@MainActor
@Observable
public final class RecentStore {
    public private(set) var entries: [RecentEntry] = []
    public let limit: Int
    private let fileURL: URL?

    /// `fileURL` `nil` keeps everything in memory (previews, tests).
    public init(fileURL: URL? = RecentStore.defaultFileURL, limit: Int = 100) {
        self.fileURL = fileURL
        self.limit = limit
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([RecentEntry].self, from: data) {
            entries = saved
        }
    }

    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("recent.json")
    }

    public func record(_ relativePath: String, _ action: RecentEntry.Action, at date: Date = .now) {
        entries.removeAll { $0.relativePath == relativePath }
        entries.insert(RecentEntry(relativePath: relativePath, action: action, date: date), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()
    }

    public func remove(_ relativePath: String) {
        entries.removeAll { $0.relativePath == relativePath }
        save()
    }

    /// Drops entries whose file no longer exists, according to `exists`.
    public func prune(keeping exists: (String) -> Bool) {
        let kept = entries.filter { exists($0.relativePath) }
        guard kept.count != entries.count else { return }
        entries = kept
        save()
    }

    /// After a rename or move, keeps the entry pointing at the file.
    public func move(_ oldPath: String, to newPath: String) {
        guard let index = entries.firstIndex(where: { $0.relativePath == oldPath }) else { return }
        entries[index].relativePath = newPath
        save()
    }

    public func clear() {
        entries = []
        save()
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }
}
