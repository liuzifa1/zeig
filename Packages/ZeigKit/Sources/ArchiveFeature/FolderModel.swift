import Foundation
import Observation
import ZeigCore
import ZeigStore

/// One row of a folder list: an item, indented by how deep it sits under expanded folders.
public struct FolderRow: Identifiable, Hashable {
    public var item: FileItem
    /// 0 for items of the folder itself, 1 for items of an expanded subfolder, …
    public var depth: Int
    /// The second line instead of size and date (Recent's "Opened 2 hours ago").
    public var detail: String?
    /// The list section it's in (Recent's day groups); `nil` lists everything in one.
    public var section: String?
    public var id: String { item.id }

    public init(item: FileItem, depth: Int, detail: String? = nil, section: String? = nil) {
        self.item = item
        self.depth = depth
        self.detail = detail
        self.section = section
    }
}

/// The state of one folder screen, shared by the list (`FolderContent`) and whatever hosts it
/// (Browse's header, a pushed folder's toolbar).
///
/// Like the Files app:
/// - **Tapping a folder pushes it** (`pushed`), in every tab.
/// - **Inline expansion**: a folder's chevron shows its contents indented under it (`expanded`).
/// - **What it lists**: a folder of the library, or the Recent list (`listsRecent`), grouped by
///   day. Both get the same menus, swipes and selection toolbar.
/// - **Selection**: `isSelecting` mirrors the list's edit mode, so the + menu, the header's
///   Select button and the list's two-finger drag all enter the same mode.
@MainActor
@Observable
public final class FolderModel {
    /// The folder shown; `nil` is the library root. For Recent, where new and imported files go.
    public let folder: URL?
    /// Lists the Recent entries (newest first, by day) instead of the folder's items.
    public let listsRecent: Bool
    public private(set) var rows: [FolderRow] = []
    /// Relative paths of folders shown expanded inline.
    public var expanded: Set<String> = []

    public var isSelecting = false {
        didSet { if !isSelecting { selection = [] } }
    }
    public var selection: Set<FileItem.ID> = []

    // Sheets, alerts and pushes the list presents.
    public var isImporting = false
    /// Recent's Clear Recent, from the + menu; the Recent tab asks first.
    public var isConfirmingClear = false
    public var isCreatingFolder = false
    public var packSources: PackSources?
    public var renaming: FileItem?
    /// What the system's move sheet is moving. Separate from `isShowingMoveSheet` because
    /// SwiftUI turns the sheet's flag off before the completion handler runs, and the handler
    /// still needs these to keep Recent pointing at the files.
    public var moving: [FileItem]? {
        didSet { isShowingMoveSheet = moving != nil }
    }
    public var isShowingMoveSheet = false
    public var infoItem: FileItem?
    public var previewURL: URL?
    /// A screen to push: a folder or an archive.
    public var pushed: LibraryRoute?
    public let actions = ArchiveActions()
    /// One more action for the list's own items (Recent's Remove from Recent): in the selection
    /// toolbar's ⋯ menu, the long-press menu and the swipe actions. Not offered for items
    /// shown under an expanded folder, which aren't the list's own.
    public var extraSelectionAction: ExtraSelectionAction?

    /// See `extraSelectionAction`.
    public struct ExtraSelectionAction {
        public var title: String
        public var systemImage: String
        public var perform: @MainActor ([FileItem]) -> Void

        public init(title: String, systemImage: String, perform: @escaping @MainActor ([FileItem]) -> Void) {
            self.title = title
            self.systemImage = systemImage
            self.perform = perform
        }
    }

    /// A folder of the library; `nil` for the top.
    public convenience init(folder: URL?) {
        self.init(folder: folder, listsRecent: false)
    }

    /// The Recent tab's list.
    public static func recent() -> FolderModel {
        FolderModel(folder: nil, listsRecent: true)
    }

    private init(folder: URL?, listsRecent: Bool) {
        self.folder = folder
        self.listsRecent = listsRecent
    }

    // MARK: Navigation

    /// Tap: folders and archives push, other files open in Quick Look.
    public func open(_ item: FileItem) {
        if item.isDirectory {
            open(folder: item.url)
        } else if item.isArchive {
            pushed = .archive(item.url)
        } else {
            previewURL = item.url
        }
    }

    public func open(folder: URL) {
        pushed = .folder(folder)
    }

    // MARK: Contents

    /// Lists the folder (or Recent) again, with the expanded folders' contents under them.
    public func reload(_ library: FileLibrary, recent: RecentStore, now: Date = .now) {
        // Forget expansions of folders that are gone.
        expanded = expanded.filter { library.item(atRelativePath: $0) != nil }
        var rows: [FolderRow] = []
        // In Recent a file can be both an entry and inside an expanded folder that's another
        // entry; the list needs unique rows, so it shows up only the first time.
        var shown: Set<String> = []
        func add(_ item: FileItem, depth: Int, detail: String? = nil, section: String? = nil) {
            guard shown.insert(item.id).inserted else { return }
            rows.append(FolderRow(item: item, depth: depth, detail: detail, section: section))
            if item.isDirectory, expanded.contains(item.id) {
                for child in library.contents(of: item.url) { add(child, depth: depth + 1, section: section) }
            }
        }
        if listsRecent {
            for entry in recent.entries {
                guard let item = library.item(atRelativePath: entry.relativePath) else { continue }
                let when = entry.date.formatted(.relative(presentation: .named, unitsStyle: .wide))
                add(item, depth: 0, detail: "\(entry.action.label) \(when)", section: RecentDay.title(for: entry.date, now: now))
            }
        } else {
            for item in library.contents(of: folder) { add(item, depth: 0) }
        }
        self.rows = rows
        selection.formIntersection(rows.map(\.id))
    }

    /// The rows by section, in order (Recent's day groups; one untitled section otherwise).
    public var sections: [(title: String?, rows: [FolderRow])] {
        var sections: [(title: String?, rows: [FolderRow])] = []
        for row in rows {
            // By title, not just runs of rows: the list needs each section once.
            if let index = sections.firstIndex(where: { $0.title == row.section }) {
                sections[index].rows.append(row)
            } else {
                sections.append((row.section, [row]))
            }
        }
        return sections
    }

    /// Whether `extraSelectionAction` applies: only to the list's own items.
    public func offersExtraAction(for items: [FileItem]) -> Bool {
        guard extraSelectionAction != nil, !items.isEmpty else { return false }
        let topLevel = Set(rows.filter { $0.depth == 0 }.map(\.id))
        return items.allSatisfy { topLevel.contains($0.id) }
    }

    /// After a rename: folders shown expanded stay expanded under their new path.
    public func folderMoved(from oldPath: String, to newPath: String) {
        expanded = Set(expanded.map { path in
            if path == oldPath { return newPath }
            if path.hasPrefix(oldPath + "/") { return newPath + "/" + path.dropFirst(oldPath.count + 1) }
            return path
        })
    }

    public func toggleExpanded(_ item: FileItem, library: FileLibrary, recent: RecentStore) {
        if expanded.contains(item.id) { expanded.remove(item.id) } else { expanded.insert(item.id) }
        reload(library, recent: recent)
    }

    /// Deletes right away, from the long-press menu, a swipe or the selection toolbar. No
    /// confirmation anywhere, as in Files: deleting is already a deliberate step.
    public func delete(_ items: [FileItem], library: FileLibrary, recent: RecentStore) {
        do {
            try library.delete(items.map(\.url))
            for item in items { recent.remove(item.relativePath) }
            ZeigLog.info("files", "deleted \(items.count) item(s)")
            isSelecting = false
        } catch {
            actions.alert = AlertContent(title: "Can't delete", message: error.localizedDescription)
        }
    }

    /// New Folder with Items, then asks for the folder's name. Recent follows the files.
    public func newFolder(containing items: [FileItem], library: FileLibrary, recent: RecentStore) {
        do {
            let created = try library.newFolder(containing: items.map(\.url))
            for item in items {
                recent.move(item.relativePath, to: library.relativePath(of: created.appendingPathComponent(item.name)))
            }
            isSelecting = false
            renaming = library.item(for: created)
        } catch {
            actions.alert = AlertContent(title: "Can't create the folder", message: error.localizedDescription)
        }
    }

    /// The folder's own items (not expanded children), for the header's summary.
    public var topLevelItems: [FileItem] { rows.filter { $0.depth == 0 }.map(\.item) }

    public func items(_ ids: Set<FileItem.ID>) -> [FileItem] {
        rows.map(\.item).filter { ids.contains($0.id) }
    }

    public var selectedItems: [FileItem] { items(selection) }

    public var allSelected: Bool { !rows.isEmpty && selection.count == rows.count }

    public func toggleSelectAll() {
        selection = allSelected ? [] : Set(rows.map(\.id))
    }

    /// "3 items · 12 MB" for headers.
    public var summary: String {
        let items = topLevelItems
        let size = items.filter { !$0.isDirectory }.reduce(UInt64(0)) { $0 + $1.size }
        let count = items.count == 1 ? "1 item" : "\(items.count) items"
        return size > 0 ? "\(count) · \(ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file))" : count
    }

    /// "Browse" at the root, else the folder's name.
    public var title: String { folder?.lastPathComponent ?? "Browse" }

    /// "1 file", "12 files": Recent's header.
    public var recentSummary: String {
        let count = topLevelItems.count
        return count == 1 ? "1 file" : "\(count) files"
    }
}

/// What the create sheet compresses, and where the archive goes.
public struct PackSources: Identifiable {
    public let id = UUID()
    public var urls: [URL]
    public var folder: URL

    public init(urls: [URL], folder: URL) {
        self.urls = urls
        self.folder = folder
    }
}
