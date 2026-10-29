import ArchiveFeature
import SwiftUI
import ZeigCore
import ZeigDesign
import ZeigStore

/// The Browse tab: the app's folder (On My iPhone › Zeig in the Files app), navigated in place
/// like Files, under a Photos-style header.
///
/// - At the top with no history: `PageHeader` with "Browse", the item count and size, and +
///   and Settings at the top right (and the console, in developer mode).
/// - After moving around: a back/forward capsule on the controls' row (Files' history
///   buttons), with the folder's name and summary as the large title under it.
/// - While selecting: Select All / Deselect All, the count, and the blue checkmark (Done).
///
/// Archives push onto the tab's `NavigationStack`; folders change in place.
public struct BrowseView: View {
    /// Set by the app to open something here ("Open in Zeig" from another app).
    @Binding var openRequest: LibraryRoute?
    @State private var model = FolderModel(folder: nil, navigatesInPlace: true)
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
                .animation(.snappy(duration: 0.25), value: model.folder)
        }
        .onChange(of: openRequest) { _, route in
            guard let route else { return }
            switch route {
            case .folder(let url): model.go(to: url)
            case .archive(let url):
                let parent = url.deletingLastPathComponent()
                model.go(to: library.isInside(parent) ? parent : nil)
                model.pushed = .archive(url)
            }
            openRequest = nil
        }
    }

    @ViewBuilder
    private var header: some View {
        if model.isSelecting {
            SelectionHeader(model: model)
        } else if model.hasHistory || model.folder != nil {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    HistoryButtons(model: model)
                    Spacer(minLength: 8)
                    HStack(spacing: 10) { controls }
                        .hnGlassContainer(spacing: 10)
                }
                Text(model.title)
                    .font(fonts.font(.title))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Text(model.summary)
                    .font(fonts.font(.subtitle, .subheadline))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)
        } else {
            PageHeader {
                // Natural width: otherwise PageHeader's minimumScaleFactor lets the title shrink
                // to make room the controls don't need. Root titles are always short.
                Text(model.title).font(fonts.font(.title)).fixedSize()
            } subtitle: {
                Text(model.summary).font(fonts.font(.subtitle, .subheadline))
            } controls: {
                controls
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
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

/// Back and forward through the folders visited, in one glass capsule (the Files app's history
/// buttons).
struct HistoryButtons: View {
    let model: FolderModel

    var body: some View {
        HStack(spacing: 0) {
            Button { model.goBack() } label: {
                PageHeaderIcon("chevron.backward")
            }
            .disabled(!model.canGoBack)
            .opacity(model.canGoBack ? 1 : 0.3)
            .accessibilityLabel("Back")
            Button { model.goForward() } label: {
                PageHeaderIcon("chevron.forward")
            }
            .disabled(!model.canGoForward)
            .opacity(model.canGoForward ? 1 : 0.3)
            .accessibilityLabel("Forward")
        }
        .padding(.horizontal, 4)
        .pageHeaderControl(in: Capsule())
    }
}
