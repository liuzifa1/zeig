import ArchiveFeature
import BrowseFeature
import RecentFeature
import SearchFeature
import SettingsFeature
import SwiftUI
import ZeigCore
import ZeigDesign
import ZeigStore

/// The three tabs, the Settings and Console sheets, and files other apps send to Zeig.
///
/// - Tabs: Browse, Recent, and Search in the tab bar's dedicated search slot
///   (`Tab(role: .search)`). `.tabViewSearchActivation(.searchTabSelection)` keeps Search a
///   separate glass button on iOS 26+ (iOS 27 would otherwise group it with the other tabs).
/// - The search field is attached by `SearchView`, outside its NavigationStack, not here on
///   the TabView: on the TabView every tab gets a hidden search drawer that breaks the lists'
///   bounce under the Browse and Recent headers (see `SearchSession`).
/// - "Open in Zeig" from another app: the file is moved or copied into the app's folder and
///   opened on the Browse tab.
struct RootView: View {
    enum AppTab: Hashable {
        case browse, recent, search
    }

    @State private var selection = AppTab.browse
    @State private var search = SearchSession()
    @State private var showsSettings = false
    @State private var showsConsole = false
    @State private var openRequest: LibraryRoute?
    @State private var openError: String?
    @Environment(FileLibrary.self) private var library
    @Environment(RecentStore.self) private var recent
    @Environment(AppSettings.self) private var settings

    var body: some View {
        TabView(selection: $selection) {
            Tab("Browse", systemImage: "folder", value: AppTab.browse) {
                BrowseView(openRequest: $openRequest)
            }
            Tab("Recent", systemImage: "clock", value: AppTab.recent) {
                RecentView()
            }
            Tab(value: AppTab.search, role: .search) {
                SearchView(session: search)
            }
        }
        .modifier(SearchTabActivation())
        .modifier(AdaptiveTabStyle())
        .environment(\.showSettings, ShowSettingsAction { showsSettings = true })
        .environment(\.showConsole, ShowConsoleAction { showsConsole = true })
        .onAppear {
            // The picture-in-picture window's "back to app" button opens the full console.
            ConsolePictureInPicture.shared.onRestore = {
                showsSettings = false
                showsConsole = true
            }
        }
        .onChange(of: settings.capturesNativeOutput, initial: true) { _, capture in
            if capture && settings.developerMode {
                NativeOutputCapture.start()
            } else if NativeOutputCapture.isRunning {
                NativeOutputCapture.stop()
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showsConsole) {
            ConsoleView()
        }
        .onOpenURL(perform: open)
        .alert("Can't open the file", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openError ?? "")
        }
    }

    private func open(_ url: URL) {
        guard url.isFileURL else { return }
        do {
            let adopted = try library.adoptOpenedFile(url)
            recent.record(library.relativePath(of: adopted), .imported)
            guard let item = library.item(for: adopted) else { return }
            showsSettings = false
            selection = .browse
            openRequest = LibraryOpen.route(for: item)
        } catch {
            openError = error.localizedDescription
        }
    }
}

/// On iOS 26+, keeps the search tab a separate glass button and focuses the field when it's
/// selected.
private struct SearchTabActivation: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabViewSearchActivation(.searchTabSelection)
        } else {
            content
        }
    }
}

/// Sidebar on iPad; the plain tab bar on iPhone, where Search keeps its own glass button
/// (the sidebar-adaptable style folds it into the tab group).
private struct AdaptiveTabStyle: ViewModifier {
    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content.tabViewStyle(.automatic)
        }
    }
}
