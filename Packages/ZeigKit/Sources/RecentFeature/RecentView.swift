import ArchiveFeature
import SwiftUI
import ZeigCore
import ZeigDesign
import ZeigStore

/// The Recent tab: files Zeig opened, created, extracted or imported, newest first, grouped
/// by day. Everything listed lives in the app's folder, so it always reopens.
///
/// The list is `FolderContent`, the same as Browse's, so it has everything Browse has: the
/// long-press menu, swipe to delete, selecting with the toolbar, folders that push on tap and
/// expand with their chevron, and the + menu. Recent adds Remove from Recent (in the menu, the
/// toolbar's ⋯ and the full swipe), which only takes files off the list, and Clear Recent.
public struct RecentView: View {
    @Environment(RecentStore.self) private var recent
    @Environment(FileLibrary.self) private var library
    @Environment(\.showSettings) private var showSettings
    @Environment(\.showConsole) private var showConsole
    @Environment(AppSettings.self) private var settings
    @Environment(\.fontTheme) private var fonts
    @State private var model = FolderModel.recent()

    public init() {}

    public var body: some View {
        @Bindable var model = model
        NavigationStack {
            FolderContent(model: model)
                .pageHeader {
                    if model.isSelecting {
                        SelectionHeader(model: model)
                    } else {
                        PageHeader {
                            Text("Recent").font(fonts.font(.title)).fixedSize()
                        } subtitle: {
                            Text(model.recentSummary).font(fonts.font(.subtitle, .subheadline))
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
                .confirmationDialog("Clear the Recent list?", isPresented: $model.isConfirmingClear, titleVisibility: .visible) {
                    Button("Clear Recent", role: .destructive) { recent.clear() }
                } message: {
                    Text("The files themselves stay where they are.")
                }
        }
        .onAppear {
            recent.prune { library.item(atRelativePath: $0) != nil }
            model.extraSelectionAction = .init(title: "Remove from Recent", systemImage: "minus.circle") { items in
                for item in items { recent.remove(item.relativePath) }
                model.isSelecting = false
            }
        }
    }
}
