import Foundation
import Observation
import ZeigCore
import ZeigStore

/// One row of a folder list: an item, indented by how deep it sits under expanded folders.
public struct FolderRow: Identifiable, Hashable {
    public var item: FileItem
    /// 0 for items of the folder itself, 1 for items of an expanded subfolder, …
    public var depth: Int
    public var id: String { item.id }
}

/// The state of one folder screen, shared by the list (`FolderContent`) and whatever hosts it
/// (Browse's header, a pushed folder's toolbar).
///
/// Like the Files app:
/// - **Navigation in place** with back/forward history (`go(to:)`, `goBack()`, `goForward()`).
///   Browse uses this; a folder pushed from Recent or Search pushes subfolders instead
///   (`navigatesInPlace == false`).
/// - **Inline expansion**: a folder's chevron shows its contents indented under it (`expanded`).
/// - **Selection**: `isSelecting` mirrors the list's edit mode, so the + menu, the header's
///   Select button and the list's two-finger drag all enter the same mode.
@MainActor
@Observable
public final class FolderModel {
    /// The folder shown; `nil` is the library root.
    public private(set) var folder: URL?
    public let navigatesInPlace: Bool
    public private(set) var rows: [FolderRow] = []
    /// Relative paths of folders shown expanded inline.
    public var expanded: Set<String> = []

    private var backStack: [URL?] = []
    private var forwardStack: [URL?] = []

    public var isSelecting = false {
        didSet { if !isSelecting { selection = [] } }
    }
    public var selection: Set<FileItem.ID> = []

    // Sheets, alerts and pushes the list presents.
    public var isImporting = false
    public var isCreatingFolder = false
    public var packSources: PackSources?
    public var renaming: FileItem?
    public var moving: [FileItem]?
    public var infoItem: FileItem?
    public var previewURL: URL?
    /// A screen to push (an archive; a folder when not navigating in place).
    public var pushed: LibraryRoute?
    public let actions = ArchiveActions()

    public init(folder: URL?, navigatesInPlace: Bool = false) {
        self.folder = folder
        self.navigatesInPlace = navigatesInPlace
    }

    // MARK: Navigation

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }
    public var hasHistory: Bool { canGoBack || canGoForward }

    public func go(to folder: URL?) {
        guard folder != self.folder else { return }
        backStack.append(self.folder)
        forwardStack.removeAll()
        moveTo(folder)
    }

    public func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(folder)
        moveTo(previous)
    }

    public func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(folder)
        moveTo(next)
    }

    private func moveTo(_ folder: URL?) {
        self.folder = folder
        isSelecting = false
        needsReload = true
    }

    /// Set when the folder changed; the view reloads with the library it has at hand.
    public private(set) var needsReload = true

    // MARK: Contents

    public func reload(_ library: FileLibrary) {
        needsReload = false
        // Forget expansions of folders that are gone.
        expanded = expanded.filter { library.item(atRelativePath: $0) != nil }
        var rows: [FolderRow] = []
        func add(_ folder: URL?, depth: Int) {
            for item in library.contents(of: folder) {
                rows.append(FolderRow(item: item, depth: depth))
                if item.isDirectory, expanded.contains(item.id) { add(item.url, depth: depth + 1) }
            }
        }
        add(folder, depth: 0)
        self.rows = rows
        selection.formIntersection(rows.map(\.id))
    }

    public func toggleExpanded(_ item: FileItem, library: FileLibrary) {
        if expanded.contains(item.id) { expanded.remove(item.id) } else { expanded.insert(item.id) }
        reload(library)
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
