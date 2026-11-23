import ArchiveFeature
import SwiftUI
import ZeigCore
import ZeigDesign
import ZeigStore

/// The Browse tab: the top of the app's folder (On My iPhone › Zeig in the Files app) under a
/// Photos-style header.
///
/// - `PageHeader` with "Browse", the item count and size, and + and Settings at the top right
///   (and the console, in developer mode).
/// - While selecting: Select All / Deselect All, the count, and the blue checkmark (Done).
///
/// The list is `FolderContent`, the same as Recent's and every pushed folder's: tapping a
/// folder or an archive pushes it, and a folder's chevron expands it in place.
public struct BrowseView: View {
    /// Set by the app to open something here ("Open in Zeig" from another app).
    @Binding var openRequest: LibraryRoute?
    @State private var model = FolderModel(folder: nil)
    @Environment(\.showSettings) private var showSettings
    @Environment(\.showConsole) private var showConsole
    @Environment(AppSettings.self) private var settings
    @Environment(\.fontTheme) private var fonts
    @Environment(FileLibrary.self) private var library

    public init(openRequest: Binding<LibraryRoute?>) {
        _openRequest = openRequest
    }

    public var body: some View {
        NavigationStack {
            FolderContent(model: model)
                .pageHeader { header }
        }
        .onChange(of: openRequest) { _, route in
            guard let route else { return }
            openRequest = nil
            Task { await show(route) }
        }
    }

    /// Pushes `route` from the top, popping whatever was pushed first.
    private func show(_ route: LibraryRoute) async {
        if case .folder(let url) = route, !library.isInside(url) || url.standardizedFileURL == library.root.standardizedFileURL {
            model.pushed = nil
            return
        }
        if model.pushed != nil {
            model.pushed = nil
            // Let the pop finish, or the push replaces the screen without animating.
            try? await Task.sleep(for: .milliseconds(450))
        }
        model.pushed = route
    }

    @ViewBuilder
    private var header: some View {
        if model.isSelecting {
            SelectionHeader(model: model)
        } else {
            PageHeader {
                // Natural width: otherwise PageHeader's minimumScaleFactor lets the title shrink
                // to make room the controls don't need. Root titles are always short.
                Text(model.title).font(fonts.font(.title)).fixedSize()
            } subtitle: {
                Text(model.summary).font(fonts.font(.subtitle, .subheadline))
            } controls: {
                if settings.developerMode {
                    Button { showConsole() } label: { PageHeaderIcon("terminal") }
                        .pageHeaderControl(in: Circle())
                        .accessibilityLabel("Console")
                }
                AddMenu(model: model) { PageHeaderIcon("plus") }
                    .pageHeaderControl(in: Circle())
                Button { showSettings() } label: { PageHeaderIcon("gearshape") }
                    .pageHeaderControl(in: Circle())
                    .accessibilityLabel("Settings")
            }
        }
    }
}
