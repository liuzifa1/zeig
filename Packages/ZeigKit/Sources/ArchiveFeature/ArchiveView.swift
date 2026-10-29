import QuickLook
import SwiftUI
import ZeigBackends
import ZeigCore
import ZeigDesign
import ZeigStore

/// What's in an archive, and the opened listing shared by its folder screens.
@MainActor
@Observable
final class ArchiveModel {
    let url: URL
    var listing: ArchiveListing?
    var tree = ArchiveTree(entries: [])
    var password: String?
    var failed = false
    let actions = ArchiveActions()

    init(url: URL) {
        self.url = url
    }

    func load(service: ArchiveService) async {
        guard listing == nil else { return }
        guard let (listing, password) = await actions.open(url, service: service) else {
            failed = true
            return
        }
        self.listing = listing
        self.password = password
        tree = ArchiveTree(entries: listing.entries)
    }

    var summary: String {
        guard let listing else { return url.lastPathComponent }
        let files = listing.entries.filter { !$0.isDirectory }
        let size = files.reduce(UInt64(0)) { $0 + $1.size }
        let count = files.count == 1 ? "1 file" : "\(files.count) files"
        let format = listing.format?.displayName ?? "Archive"
        return "\(format) · \(count) · \(size.formattedByteCount)"
    }
}

/// A folder inside an opened archive, pushed when you tap one.
struct ArchiveFolderRoute: Hashable {
    let archive: URL
    let path: String
}

/// An archive's contents: browse its folders, preview a file (tap), extract one item
/// (long-press), or extract everything into a new folder next to the archive.
public struct ArchiveView: View {
    @State private var model: ArchiveModel
    @Environment(AppSettings.self) private var settings
    @Environment(FileLibrary.self) private var library
    @Environment(RecentStore.self) private var recent
    @State private var openedFolder: URL?
    @State private var showsInfo = false

    public init(url: URL) {
        _model = State(initialValue: ArchiveModel(url: url))
    }

    private var service: ArchiveService { ArchiveService(settings: settings.routing) }

    public var body: some View {
        ArchiveFolderList(model: model, path: "")
            .navigationTitle(model.url.lastPathComponent)
            .inlineNavigationTitle()
            .pinnedTopBar {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if model.listing?.backend == .rars { ExperimentalBadge() }
                    }
                    Spacer()
                    Button {
                        Task { await extract(nil) }
                    } label: {
                        Label("Extract All", systemImage: "arrow.down.doc")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .frame(height: pageHeaderControlSize)
                    }
                    .pageHeaderControl(in: Capsule())
                    .disabled(model.listing == nil)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 10)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Test Archive", systemImage: "checkmark.seal") {
                            guard let listing = model.listing else { return }
                            Task { await model.actions.test(listing, password: model.password, service: service) }
                        }
                        ShareLink(item: model.url)
                        Button("Info", systemImage: "info.circle") { showsInfo = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                    .disabled(model.listing == nil)
                }
            }
            .navigationDestination(for: ArchiveFolderRoute.self) { route in
                ArchiveFolderList(model: model, path: route.path)
                    .navigationTitle(route.path.split(separator: "/").last.map(String.init) ?? "")
                    .inlineNavigationTitle()
                    .softTopScrollEdge()
            }
            .navigationDestination(item: $openedFolder) { FolderView(folder: $0) }
            .alert("Extracted", isPresented: Binding(get: { model.actions.extracted != nil }, set: { if !$0 { model.actions.extracted = nil } })) {
                Button("Show Folder") {
                    openedFolder = model.actions.extracted
                    model.actions.extracted = nil
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("The files are in “\(model.actions.extracted?.lastPathComponent ?? "")”.")
            }
            .sheet(isPresented: $showsInfo) {
                if let listing = model.listing { ArchiveInfoView(listing: listing) }
            }
            .archiveActions(model.actions)
            .task {
                await model.load(service: service)
                if model.listing != nil { recent.record(library.relativePath(of: model.url), .opened) }
            }
            .environment(\.extractArchiveItems, ExtractItemsAction { entries in await extract(entries) })
    }

    private func extract(_ entries: [ArchiveEntry]?) async {
        await model.actions.extract(
            model.url, listing: model.listing, entries: entries, password: model.password,
            service: service, library: library, recent: recent
        )
    }
}

/// Lets a folder level inside an archive ask the archive screen to extract some entries.
private struct ExtractItemsAction {
    var action: @MainActor ([ArchiveEntry]) async -> Void
    @MainActor func callAsFunction(_ entries: [ArchiveEntry]) async { await action(entries) }
}

private extension EnvironmentValues {
    @Entry var extractArchiveItems = ExtractItemsAction { _ in }
}

/// One folder level of an open archive.
private struct ArchiveFolderList: View {
    let model: ArchiveModel
    let path: String
    @Environment(AppSettings.self) private var settings
    @Environment(\.extractArchiveItems) private var extractItems
    @State private var previewURL: URL?
    @State private var previewFolder: URL?
    @Environment(\.fontTheme) private var fonts

    var body: some View {
        List(model.tree.children(of: path)) { node in
            Group {
                if node.isDirectory {
                    NavigationLink(value: ArchiveFolderRoute(archive: model.url, path: node.path)) { row(node) }
                } else {
                    Button { Task { await preview(node) } } label: { row(node) }
                        .buttonStyle(.plain)
                }
            }
            .contextMenu {
                Button(node.isDirectory ? "Extract Folder" : "Extract", systemImage: "arrow.down.doc") {
                    Task { await extractItems(model.tree.entries(for: node)) }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.listing == nil && !model.failed {
                ProgressView()
            } else if model.failed {
                ContentUnavailableView("Can't Open Archive", systemImage: "exclamationmark.triangle")
            } else if model.tree.children(of: path).isEmpty {
                ContentUnavailableView("Empty", systemImage: "doc.zipper")
            }
        }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { _, url in
            // The preview's copy is temporary; remove it when the preview closes.
            if url == nil, let folder = previewFolder {
                try? FileManager.default.removeItem(at: folder)
                previewFolder = nil
            }
        }
    }

    private func row(_ node: ArchiveTree.Node) -> some View {
        HStack(spacing: 12) {
            FileIcon(isDirectory: node.isDirectory, format: FormatDetector.format(forName: node.name), fileName: node.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).font(fonts.font(.fileName)).lineLimit(2)
                Text(detail(node)).font(fonts.font(.subtitle)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if node.entry?.isEncrypted == true {
                Image(systemName: "lock.fill").foregroundStyle(.secondary).accessibilityLabel("Encrypted")
            }
        }
        .contentShape(Rectangle())
    }

    private func detail(_ node: ArchiveTree.Node) -> String {
        var parts = node.isDirectory && node.size == 0 ? [] : [node.size.formattedByteCount]
        if let date = node.entry?.modified { parts.append(date.formatted(date: .abbreviated, time: .shortened)) }
        return parts.joined(separator: " · ")
    }

    /// Extracts one file to a temporary folder and opens it in Quick Look, asking for the
    /// password first if the entry is encrypted.
    private func preview(_ node: ArchiveTree.Node) async {
        guard let listing = model.listing, let entry = node.entry else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Preview-\(UUID().uuidString)")
        let service = ArchiveService(settings: settings.routing)
        do {
            let result = try await model.actions.withPassword(for: model.url, initial: model.password) { (password) throws(ArchiveError) in
                try await service.extract(listing, entries: [entry], to: folder, password: password)
            }
            guard let result else {
                try? FileManager.default.removeItem(at: folder)
                return
            }
            model.password = result.password
            previewFolder = folder
            previewURL = folder.appendingPathComponent(node.path)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            model.actions.alert = AlertContent(title: "Can't preview \(node.name)", message: error.message, detail: error.detail)
        }
    }
}

/// The archive's Info sheet: what's inside, how well it's compressed, how, and which engine
/// opened it. A medium-height sheet; scroll for the rest.
private struct ArchiveInfoView: View {
    let listing: ArchiveListing
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fontTheme) private var fonts

    var body: some View {
        let stats = listing.statistics
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        FileIcon(isDirectory: false, format: listing.format, fileName: listing.url.lastPathComponent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(listing.url.lastPathComponent).font(fonts.font(.fileName, .headline)).lineLimit(2)
                            Text(listing.format.map { "\($0.displayName) archive" } ?? "Archive")
                                .font(fonts.font(.subtitle, .subheadline))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Size") {
                    if let ratio = stats.ratio {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Compressed to \(percent(ratio))")
                                Spacer()
                                if let savings = stats.savings, savings > 0 {
                                    Text("saves \(percent(savings))").foregroundStyle(.green)
                                }
                            }
                            .font(fonts.font(.indicator))
                            ProgressView(value: min(ratio, 1))
                                .tint(ratio < 1 ? .green : .orange)
                        }
                    }
                    LabeledContent("Original", value: stats.originalSize.formattedByteCount)
                    LabeledContent("Archive", value: stats.archiveSize.formattedByteCount)
                }

                Section("Contents") {
                    LabeledContent("Files", value: "\(stats.fileCount)")
                    LabeledContent("Folders", value: "\(stats.folderCount)")
                    if stats.encryptedCount > 0 {
                        LabeledContent("Encrypted", value: stats.encryptedCount == stats.fileCount ? "All files" : "\(stats.encryptedCount) files")
                    }
                    if let newest = stats.newest {
                        LabeledContent("Newest", value: newest.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let oldest = stats.oldest, oldest != stats.newest {
                        LabeledContent("Oldest", value: oldest.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                Section("Compression") {
                    if let name = listing.info.formatName {
                        LabeledContent("Format", value: name)
                    }
                    if let method = listing.info.method {
                        LabeledContent("Method", value: method)
                    }
                    if let solid = listing.info.isSolid {
                        LabeledContent("Solid", value: solid ? "Yes" : "No")
                    }
                    if let volumes = listing.info.volumeCount, volumes > 1 {
                        LabeledContent("Parts", value: "\(volumes)")
                    }
                    if let comment = listing.info.comment {
                        LabeledContent("Comment") { Text(comment).textSelection(.enabled) }
                    }
                }

                Section {
                    HStack {
                        LabeledContent("Opened with", value: listing.backend.displayName)
                        if listing.backend == .rars { ExperimentalBadge() }
                    }
                } footer: {
                    if listing.usedFallback {
                        Text("The usual engine for this format couldn't open the file, so \(listing.backend.displayName) did.")
                    } else if listing.backend == .rars {
                        Text("You chose to open RAR archives with the experimental rars engine in Settings.")
                    }
                }
            }
            .environment(\.defaultMinListRowHeight, 36)
            .navigationTitle("Info")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}
