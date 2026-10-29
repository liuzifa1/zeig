import ArchiveFeature
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import ZeigCore
import ZeigDesign
import ZeigStore

/// The Recent tab: files Zeig opened, created, extracted or imported, newest first, grouped
/// by day. Everything listed lives in the app's folder, so it always reopens.
public struct RecentView: View {
    @Environment(RecentStore.self) private var recent
    @Environment(FileLibrary.self) private var library
    @Environment(\.showSettings) private var showSettings
    @Environment(\.showConsole) private var showConsole
    @Environment(AppSettings.self) private var settings
    @State private var previewURL: URL?
    @State private var isImporting = false
    @State private var confirmingClear = false
    @State private var importError: String?
    @State private var selection: Set<String> = []
    @State private var pushed: LibraryRoute?
    @Environment(\.fontTheme) private var fonts

    public init() {}

    private struct Row: Identifiable {
        var entry: RecentEntry
        var item: FileItem
        var id: String { entry.id }
    }

    private var rows: [Row] {
        recent.entries.compactMap { entry in
            library.item(atRelativePath: entry.relativePath).map { Row(entry: entry, item: $0) }
        }
    }

    public var body: some View {
        // Read so the list refreshes after files change (renames, deletes elsewhere).
        let _ = library.changeCount
        let rows = rows
        NavigationStack {
            List(selection: $selection) {
                ForEach(Self.sections(rows.map(\.entry.date)), id: \.title) { section in
                    Section {
                        ForEach(rows.filter { section.contains($0.entry.date) }) { row in
                            FileRow(item: row.item, detail: detail(row))
                                .tag(row.id)
                                .swipeActions {
                                    // Removes from the list only, right away: no confirmation, so the
                                    // destructive role's instant row removal matches the data.
                                    Button("Remove", systemImage: "minus.circle", role: .destructive) {
                                        recent.remove(row.entry.relativePath)
                                    }
                                }
                        }
                    } header: {
                        Text(section.title)
                            .font(fonts.font(.indicator, .subheadline))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
            // The header already sits above the list; the default top margin doubled the gap
            // between its subtitle and the first day.
            .contentMargins(.top, 0, for: .scrollContent)
            .environment(\.defaultMinListHeaderHeight, 24)
            .contextMenu(forSelectionType: String.self) { ids in
                if let row = rows.first(where: { ids.contains($0.id) }) {
                    Button("Open", systemImage: "arrow.up.forward") { open(row.item) }
                    ShareLink(item: row.item.url)
                    Divider()
                    Button("Remove from Recent", systemImage: "minus.circle", role: .destructive) {
                        recent.remove(row.entry.relativePath)
                    }
                }
            } primaryAction: { ids in
                selection = []
                if let row = rows.first(where: { ids.contains($0.id) }) { open(row.item) }
            }
            .navigationDestination(item: $pushed) { route in
                switch route {
                case .folder(let url): FolderView(folder: url)
                case .archive(let url): ArchiveView(url: url)
                }
            }
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing Yet", systemImage: "clock")
                    } description: {
                        Text("Archives you open, create or extract show up here.")
                    }
                }
            }
            .pageHeader {
                PageHeader {
                    Text("Recent").font(fonts.font(.title)).fixedSize()
                } subtitle: {
                    Text(rows.count == 1 ? "1 file" : "\(rows.count) files").font(fonts.font(.subtitle, .subheadline))
                } controls: {
                    if settings.developerMode {
                        Button { showConsole() } label: { PageHeaderIcon("terminal") }
                            .pageHeaderControl(in: Circle())
                            .accessibilityLabel("Console")
                    }
                    Menu {
                        Button("Import from Files…", systemImage: "square.and.arrow.down") { isImporting = true }
                        Divider()
                        Button("Clear Recent", systemImage: "trash", role: .destructive) { confirmingClear = true }
                            .disabled(recent.entries.isEmpty)
                    } label: {
                        PageHeaderIcon("plus")
                    }
                    .pageHeaderControl(in: Circle())
                    .accessibilityLabel("Add")
                    Button { showSettings() } label: { PageHeaderIcon("gearshape") }
                        .pageHeaderControl(in: Circle())
                        .accessibilityLabel("Settings")
                }
            }
            .quickLookPreview($previewURL)
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                do {
                    for copy in try library.importFiles(try result.get()) {
                        recent.record(library.relativePath(of: copy), .imported)
                    }
                } catch {
                    importError = error.localizedDescription
                }
            }
            .confirmationDialog("Clear the Recent list?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear Recent", role: .destructive) { recent.clear() }
            } message: {
                Text("The files themselves stay where they are.")
            }
            .alert("Can't import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .onAppear { recent.prune { library.item(atRelativePath: $0) != nil } }
        }
    }

    private func detail(_ row: Row) -> String {
        "\(row.entry.action.label) \(row.entry.date.formatted(.relative(presentation: .named)))"
    }

    private func open(_ item: FileItem) {
        if let route = LibraryOpen.route(for: item) { pushed = route } else { previewURL = item.url }
    }

    /// Today, Yesterday, This Week, Earlier: only the ones with entries.
    struct DaySection {
        var title: String
        var contains: (Date) -> Bool
    }

    static func sections(_ dates: [Date], now: Date = .now, calendar: Calendar = .current) -> [DaySection] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        let all = [
            DaySection(title: "Today") { $0 >= startOfToday },
            DaySection(title: "Yesterday") { $0 >= startOfYesterday && $0 < startOfToday },
            DaySection(title: "This Week") { $0 >= startOfWeek && $0 < startOfYesterday },
            DaySection(title: "Earlier") { $0 < startOfWeek },
        ]
        return all.filter { section in dates.contains(where: section.contains) }
    }
}
