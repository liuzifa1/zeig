import SwiftUI
import ZeigCore
import ZeigDesign
import ZeigStore

/// Settings › Storage: what takes space in the app's folder, and ways to free some.
///
/// - A bar of the folder's bytes by kind (archives, extracted folders, other files), with how
///   much the device has free.
/// - **Already extracted**: archives with their extracted folder next to them. The archive can
///   usually go; the folder keeps the contents.
/// - **Temporary files**: copies made to preview files inside archives and to paste files.
/// - **Largest files**, which can be selected and deleted together.
///
/// A swipe deletes one item at once, as in the file lists. Deleting several asks first,
/// with how much it frees: it's permanent, and a cleanup page makes it easy to pick a lot.
struct StorageView: View {
    @Environment(FileLibrary.self) private var library
    @Environment(RecentStore.self) private var recent
    @Environment(\.fontTheme) private var fonts
    @State private var report: StorageReport?
    @State private var temporarySize: UInt64 = 0
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var confirming: Deletion?
    @State private var errorMessage: String?

    /// A deletion waiting for the confirmation.
    private struct Deletion: Identifiable {
        let id = UUID()
        var title: String
        var entries: [StorageReport.Entry]
        var size: UInt64 { entries.reduce(0) { $0.addingSaturating($1.size) } }
    }

    var body: some View {
        List(selection: $selection) {
            // While selecting, only the files that can be selected: in edit mode every row
            // shows a selection circle, tagged or not.
            if !isSelecting { Section { overview } }
            if let report {
                if !isSelecting {
                    if !report.extracted.isEmpty { extractedSection(report.extracted) }
                    if temporarySize > 0 { temporarySection }
                }
                largestSection(report.largestFiles)
            }
        }
        .overlay {
            if report == nil { ProgressView() }
        }
        .navigationTitle("Storage")
        .inlineNavigationTitle()
        .modifier(StorageEditMode(isSelecting: $isSelecting))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isSelecting ? "Done" : "Select") {
                    isSelecting.toggle()
                    if !isSelecting { selection = [] }
                }
                .disabled(report?.largestFiles.isEmpty ?? true)
            }
            #if os(iOS)
            if isSelecting {
                ToolbarItem(placement: .bottomBar) {
                    let entries = selectedEntries
                    Button(role: .destructive) {
                        confirming = Deletion(title: entries.count == 1 ? "Delete 1 file?" : "Delete \(entries.count) files?", entries: entries)
                    } label: {
                        Text(entries.isEmpty ? "Delete" : "Delete \(entries.count) · \(entries.reduce(UInt64(0)) { $0.addingSaturating($1.size) }.formattedByteCount)")
                    }
                    .tint(.red)
                    .disabled(entries.isEmpty)
                }
            }
            #endif
        }
        .confirmationDialog(confirming?.title ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible, presenting: confirming) { deletion in
            Button("Delete", role: .destructive) { delete(deletion.entries) }
        } message: { deletion in
            Text("Frees \(deletion.size.formattedByteCount). This can't be undone.")
        }
        .alert("Can't delete", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: library.changeCount) { await reload() }
        .refreshable { await reload() }
    }

    // MARK: Sections

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(report.map { $0.total.formattedByteCount } ?? "…")
                    .font(fonts.font(.title, .title2)).bold()
                Text("in \(AppInfo.displayName)")
                    .font(fonts.font(.subtitle, .subheadline))
                    .foregroundStyle(.secondary)
            }
            StorageBar(report: report)
            HStack(spacing: 14) {
                ForEach(StorageReport.Kind.allCases, id: \.self) { kind in
                    HStack(spacing: 5) {
                        Circle().fill(kind.color).frame(width: 8, height: 8)
                        Text(kind.title)
                    }
                }
            }
            .font(fonts.font(.indicator, .caption))
            .foregroundStyle(.secondary)
            if let free = Self.freeSpace(at: library.root) {
                Text("\(free.available.formattedByteCount) free of \(free.total.formattedByteCount) on this device")
                    .font(fonts.font(.subtitle, .footnote))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func extractedSection(_ pairs: [StorageReport.Extracted]) -> some View {
        Section {
            ForEach(pairs) { pair in
                row(pair.archive, detail: extractedDetail(pair))
                    .swipeActions {
                        // Immediate, so the destructive role's instant row removal matches.
                        Button("Delete Archive", systemImage: "trash", role: .destructive) { delete([pair.archive]) }
                    }
            }
            if pairs.count > 1 {
                Button("Delete These \(pairs.count) Archives", role: .destructive) {
                    confirming = Deletion(title: "Delete \(pairs.count) archives?", entries: pairs.map(\.archive))
                }
            }
        } header: {
            Text("Already extracted")
        } footer: {
            Text("Each of these archives has a folder of the same name next to it, most likely with its contents. Deleting an archive keeps its folders.")
        }
    }

    private var temporarySection: some View {
        Section {
            LabeledContent("Temporary files", value: temporarySize.formattedByteCount)
            Button("Clear Temporary Files") { clearTemporaryFiles() }
        } footer: {
            Text("Copies made to preview files inside archives and to paste files. Nothing you keep is in here.")
        }
    }

    private func largestSection(_ entries: [StorageReport.Entry]) -> some View {
        Section {
            if entries.isEmpty {
                Text("No files yet.").foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                row(entry, detail: detail(entry))
                    .tag(entry.id)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { delete([entry]) }
                    }
            }
        } header: {
            Text("Largest files")
        } footer: {
            if !entries.isEmpty {
                Text("Tap Select to delete several at once.")
            }
        }
    }

    private func row(_ entry: StorageReport.Entry, detail: String) -> some View {
        HStack(spacing: 10) {
            FileThumbnail(url: entry.url, isDirectory: entry.isDirectory, format: FormatDetector.format(forName: entry.name), modified: entry.modified)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(fonts.font(.fileName)).lineLimit(2)
                Text(detail).font(fonts.font(.subtitle)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(entry.size.formattedByteCount)
                .font(fonts.font(.indicator, .subheadline))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// "Extracted to “photos” · 12 MB", or "to “photos” and 2 more" when extracted again.
    private func extractedDetail(_ pair: StorageReport.Extracted) -> String {
        let more = pair.folders.count > 1 ? " and \(pair.folders.count - 1) more" : ""
        return "Extracted to “\(pair.folders[0].name)”\(more) · \(pair.foldersSize.formattedByteCount)"
    }

    private func detail(_ entry: StorageReport.Entry) -> String {
        let folder = (entry.relativePath as NSString).deletingLastPathComponent
        let date = entry.modified.formatted(date: .abbreviated, time: .omitted)
        return folder.isEmpty ? date : "In \(folder) · \(date)"
    }

    // MARK: Actions

    private var selectedEntries: [StorageReport.Entry] {
        report?.largestFiles.filter { selection.contains($0.id) } ?? []
    }

    private func reload() async {
        let root = library.root
        let temporary = FileManager.default.temporaryDirectory
        let (report, temporarySize) = await Task.detached(priority: .userInitiated) {
            (StorageReport.scan(root), StorageReport.size(of: temporary))
        }.value
        self.report = report
        self.temporarySize = temporarySize
        selection.formIntersection(report.largestFiles.map(\.id))
    }

    private func delete(_ entries: [StorageReport.Entry]) {
        let ids = Set(entries.map(\.id))
        // Off the lists right away, so a swiped row doesn't come back before the rescan.
        report?.largestFiles.removeAll { ids.contains($0.id) }
        report?.extracted.removeAll { ids.contains($0.archive.id) }
        selection.subtract(ids)
        do {
            try library.delete(entries.map(\.url))
            for entry in entries { recent.remove(entry.relativePath) }
            ZeigLog.info("storage", "deleted \(entries.count) item(s)")
        } catch {
            errorMessage = error.localizedDescription
            library.noteChange()
        }
        if selection.isEmpty { isSelecting = false }
    }

    private func clearTemporaryFiles() {
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory
        for url in (try? fileManager.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? [] {
            try? fileManager.removeItem(at: url)
        }
        ZeigLog.info("storage", "cleared temporary files (\(temporarySize.formattedByteCount))")
        temporarySize = StorageReport.size(of: temporary)
    }

    private static func freeSpace(at url: URL) -> (available: UInt64, total: UInt64)? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let available = values.volumeAvailableCapacityForImportantUsage, let total = values.volumeTotalCapacity
        else { return nil }
        return (UInt64(max(0, available)), UInt64(max(0, total)))
    }
}

/// The folder's bytes by kind, as one rounded bar.
private struct StorageBar: View {
    let report: StorageReport?

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                if let report, report.total > 0 {
                    ForEach(StorageReport.Kind.allCases, id: \.self) { kind in
                        let share = Double(report.size(of: kind)) / Double(report.total)
                        if share > 0 {
                            kind.color.frame(width: max(3, (geometry.size.width - 4) * share))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 14)
        .background(Color.secondary.opacity(0.15))
        .clipShape(Capsule())
        .animation(.snappy, value: report?.total)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let report else { return "Measuring" }
        return StorageReport.Kind.allCases
            .map { "\($0.title) \(report.size(of: $0).formattedByteCount)" }
            .joined(separator: ", ")
    }
}

private extension StorageReport.Kind {
    var title: String {
        switch self {
        case .archives: "Archives"
        case .extracted: "Extracted"
        case .other: "Other files"
        }
    }

    var color: Color {
        switch self {
        case .archives: .orange
        case .extracted: .blue
        case .other: .gray
        }
    }
}

/// The list's edit mode while selecting (iOS only: macOS builds this package just for tests).
private struct StorageEditMode: ViewModifier {
    @Binding var isSelecting: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.environment(\.editMode, Binding(
            get: { isSelecting ? .active : .inactive },
            set: { isSelecting = $0.isEditing }
        ))
        #else
        content
        #endif
    }
}
