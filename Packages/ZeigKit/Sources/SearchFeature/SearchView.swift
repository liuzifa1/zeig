import ArchiveFeature
import QuickLook
import SwiftUI
import ZeigCore
import ZeigDesign
import ZeigStore

/// The Search tab's field state, owned by the app (kept across tab switches).
///
/// Where the field is attached matters on iOS 26+ (learned in HNReader):
/// - On the Search tab's `NavigationStack` (outside it), as `SearchView` does: the field lives
///   only in the tab bar.
/// - Inside the stack: the page also gets its own navigation-bar field.
/// - On the `TabView`: every tab's navigation bar gets a hidden search drawer that breaks the
///   other tabs' list bounce under their headers.
/// On iOS 18 the field goes in the page's navigation bar as usual.
@MainActor
@Observable
public final class SearchSession {
    public var query = ""
    public var isPresented = false

    public init() {}

    /// `true` where the field belongs in the tab bar (iOS 26+).
    public static var fieldBelongsToTabView: Bool {
        #if os(iOS)
        if #available(iOS 26, *) { return true }
        #endif
        return false
    }
}

/// What the switch under the title filters by.
enum SearchScope: String, CaseIterable, Identifiable {
    case all, archives
    var id: String { rawValue }
}

/// The Search tab: file names anywhere in the app's folder, with a Photos-style switch
/// between all files and archives only, each showing its count.
///
/// Lives in the tab bar's search slot (`Tab(role: .search)`); the large "Search" title is a
/// leading toolbar item so it never collapses, and the switch is pinned under it
/// (`pinnedTopBar`), with results scrolling under both behind the soft edge.
public struct SearchView: View {
    @Bindable var session: SearchSession
    @Environment(FileLibrary.self) private var library
    @Environment(\.showSettings) private var showSettings
    @State private var scope = SearchScope.all
    @State private var everything: [FileItem] = []
    @State private var previewURL: URL?
    @State private var selection: Set<String> = []
    @State private var pushed: LibraryRoute?
    @Environment(\.fontTheme) private var fonts

    public init(session: SearchSession) {
        self.session = session
    }

    private var query: String { session.query.trimmingCharacters(in: .whitespaces) }

    private func matches(_ scope: SearchScope) -> [FileItem] {
        guard !query.isEmpty else { return [] }
        return everything
            .filter { scope == .all || $0.isArchive }
            .filter { $0.name.localizedStandardContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public var body: some View {
        NavigationStack {
            let results = matches(scope)
            List(results, selection: $selection) { item in
                FileRow(item: item, detail: detail(item)).tag(item.id)
            }
            .listStyle(.plain)
            .contextMenu(forSelectionType: String.self) { ids in
                if let item = results.first(where: { ids.contains($0.id) }) {
                    Button("Open", systemImage: "arrow.up.forward") { open(item) }
                    ShareLink(item: item.url)
                }
            } primaryAction: { ids in
                selection = []
                if let item = results.first(where: { ids.contains($0.id) }) { open(item) }
            }
            .navigationDestination(item: $pushed) { route in
                switch route {
                case .folder(let url): FolderView(folder: url)
                case .archive(let url): ArchiveView(url: url)
                }
            }
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView("Search Your Files", systemImage: "magnifyingglass", description: Text("Find files and archives by name."))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .pinnedTopBar {
                ScopeSwitcher(selection: $scope, options: SearchScope.allCases) { option in
                    let title = option == .all ? "All Files" : "Archives"
                    return query.isEmpty ? title : "\(title) (\(matches(option).count))"
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 10)
            }
            .softTopScrollEdge()
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #else
            .navigationTitle("Search")
            #endif
            .toolbar {
                #if os(iOS)
                LargeTitleItem("Search")
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") { showSettings() }
                }
            }
            .modifier(InlineSearchField(session: session))
            .quickLookPreview($previewURL)
        }
        .modifier(TabBarSearchField(session: session))
        .task(id: library.changeCount) { everything = library.allItems() }
    }

    private func detail(_ item: FileItem) -> String {
        let folder = (item.relativePath as NSString).deletingLastPathComponent
        if item.isDirectory { return folder.isEmpty ? "Folder" : "In \(folder)" }
        return folder.isEmpty ? item.size.formattedByteCount : "In \(folder) · \(item.size.formattedByteCount)"
    }

    private func open(_ item: FileItem) {
        if let route = LibraryOpen.route(for: item) { pushed = route } else { previewURL = item.url }
    }
}

/// iOS 26+: the field attached outside the navigation stack, so it lives in the tab bar.
private struct TabBarSearchField: ViewModifier {
    @Bindable var session: SearchSession

    func body(content: Content) -> some View {
        if SearchSession.fieldBelongsToTabView {
            content
                .searchable(text: $session.query, isPresented: $session.isPresented, prompt: "File names")
                .searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            content
        }
    }
}

/// iOS 18: the field in this page's navigation bar.
private struct InlineSearchField: ViewModifier {
    @Bindable var session: SearchSession

    func body(content: Content) -> some View {
        if SearchSession.fieldBelongsToTabView {
            content
        } else {
            content
                .searchable(text: $session.query, isPresented: $session.isPresented, prompt: "File names")
        }
    }
}
