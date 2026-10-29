import SwiftUI
import UniformTypeIdentifiers
import ZeigBackends
import ZeigCore
import ZeigDesign
import ZeigStore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Long-press menu

/// The Files-style menu for one item or a selection: Copy · Move · Share across the top, then
/// Quick Look and Open In, then Get Info, Rename, Extract or Compress, Duplicate, New Folder
/// with Items, and Delete at the bottom.
struct FileMenu: View {
    let items: [FileItem]
    let model: FolderModel
    let folder: URL
    let service: ArchiveService
    @Environment(FileLibrary.self) private var library
    @Environment(RecentStore.self) private var recent

    var body: some View {
        if !items.isEmpty {
            ControlGroup {
                Button("Copy", systemImage: "doc.on.doc") { FilePasteboard.copy(items.map(\.url)) }
                Button("Move", systemImage: "folder") { model.moving = items }
                ShareLink(items: items.map(\.url)) { Label("Share", systemImage: "square.and.arrow.up") }
            }

            if let item = items.only {
                Section {
                    if !item.isDirectory {
                        Button("Quick Look", systemImage: "eye") { model.previewURL = item.url }
                        ShareLink(item: item.url) { Label("Open In…", systemImage: "arrow.up.forward.app") }
                    }
                }
                Section {
                    Button("Get Info", systemImage: "info.circle") { model.infoItem = item }
                    Button("Rename", systemImage: "pencil") { model.renaming = item }
                    if item.isArchive {
                        Button("Extract", systemImage: "arrow.down.doc") { extract(item) }
                    } else {
                        Button("Compress", systemImage: "doc.zipper") { compress() }
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square") { duplicate() }
                    Button("New Folder with Item", systemImage: "folder.badge.plus") { newFolder() }
                }
            } else {
                Section {
                    Button("Compress \(items.count) Items", systemImage: "doc.zipper") { compress() }
                    if items.allSatisfy(\.isArchive) {
                        Button("Extract \(items.count) Archives", systemImage: "arrow.down.doc") {
                            for item in items { extract(item) }
                        }
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square") { duplicate() }
                    Button("New Folder with \(items.count) Items", systemImage: "folder.badge.plus") { newFolder() }
                }
            }
            Section {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    model.delete(items, library: library, recent: recent)
                }
            }
        }
    }

    private func extract(_ item: FileItem) {
        Task {
            await model.actions.extract(item.url, service: service, library: library, recent: recent)
        }
    }

    private func compress() {
        model.packSources = PackSources(urls: items.map(\.url), folder: folder)
    }

    private func duplicate() {
        do {
            try library.duplicate(items.map(\.url))
            model.isSelecting = false
        } catch {
            model.actions.alert = AlertContent(title: "Can't duplicate", message: error.localizedDescription)
        }
    }

    private func newFolder() {
        do {
            let created = try library.newFolder(containing: items.map(\.url))
            model.isSelecting = false
            model.renaming = library.item(for: created)
        } catch {
            model.actions.alert = AlertContent(title: "Can't create the folder", message: error.localizedDescription)
        }
    }
}

extension Array {
    /// The element, if there is exactly one.
    var only: Element? { count == 1 ? first : nil }
}

// MARK: - Selection toolbar

#if os(iOS)

/// The toolbar that replaces the tab bar while selecting (like Files): Extract, Compress, Move
/// and Delete, a gap, then ⋯ with Share, Copy N Items and New Folder with Items.
///
/// Delete doesn't ask first (`FolderModel.delete`). Move opens the system's move sheet (`FolderContent`'s `fileMover`).
struct SelectionToolbar: ToolbarContent {
    let model: FolderModel
    let folder: URL
    @Environment(FileLibrary.self) private var library
    @Environment(RecentStore.self) private var recent
    @Environment(AppSettings.self) private var settings

    private var items: [FileItem] { model.selectedItems }

    var body: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItemGroup(placement: .bottomBar) { actions }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) { more }
        } else {
            ToolbarItemGroup(placement: .bottomBar) {
                actions
                Spacer()
                more
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button("Extract", systemImage: "arrow.down.doc") { extract() }
            .disabled(items.isEmpty || !items.allSatisfy(\.isArchive))
        Button("Compress", systemImage: "doc.zipper") {
            model.packSources = PackSources(urls: items.map(\.url), folder: folder)
        }
        .disabled(items.isEmpty)
        Button("Move", systemImage: "folder") { model.moving = items }
            .disabled(items.isEmpty)
        Button("Delete", systemImage: "trash") { model.delete(items, library: library, recent: recent) }
            .disabled(items.isEmpty)
    }

    private var more: some View {
        Menu("More", systemImage: "ellipsis") {
            ShareLink(items: items.map(\.url)) { Label("Share", systemImage: "square.and.arrow.up") }
            Button(items.count == 1 ? "Copy 1 Item" : "Copy \(items.count) Items", systemImage: "doc.on.doc") {
                FilePasteboard.copy(items.map(\.url))
                model.isSelecting = false
            }
            Button("New Folder with Items", systemImage: "folder.badge.plus") { newFolder() }
        }
        .disabled(items.isEmpty)
    }

    private func extract() {
        let service = ArchiveService(settings: settings.routing)
        let urls = items.map(\.url)
        model.isSelecting = false
        Task {
            for url in urls { await model.actions.extract(url, service: service, library: library, recent: recent) }
        }
    }

    private func newFolder() {
        do {
            let created = try library.newFolder(containing: items.map(\.url))
            model.isSelecting = false
            model.renaming = library.item(for: created)
        } catch {
            model.actions.alert = AlertContent(title: "Can't create the folder", message: error.localizedDescription)
        }
    }
}

#endif

/// The header row while selecting (like Files): Select All / Deselect All, the count, and the
/// blue checkmark that ends selecting.
public struct SelectionHeader: View {
    let model: FolderModel
    @Environment(\.fontTheme) private var fonts

    public init(model: FolderModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            Text(model.selection.count == 1 ? "1 Item" : "\(model.selection.count) Items")
                .font(fonts.font(.indicator, .headline))
            HStack {
                Button(model.allSelected ? "Deselect All" : "Select All") { model.toggleSelectAll() }
                    .font(fonts.font(.indicator))
                    .padding(.horizontal, 16)
                    .frame(height: pageHeaderControlSize)
                    .pageHeaderControl(in: Capsule())
                Spacer()
                Button {
                    model.isSelecting = false
                } label: {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: pageHeaderControlSize, height: pageHeaderControlSize)
                        .background(.tint, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}

// MARK: - Info

/// Get Info for a file or folder: kind, size, item count, dates and where it is.
struct FileInfoSheet: View {
    let item: FileItem
    @Environment(FileLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var folderSummary: (count: Int, size: UInt64)?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        FileThumbnail(url: item.url, isDirectory: item.isDirectory, format: item.format, modified: item.modified)
                        Text(item.name).font(.headline).lineLimit(3)
                    }
                }
                Section {
                    LabeledContent("Kind", value: kind)
                    if item.isDirectory {
                        LabeledContent("Contains", value: folderSummary.map { "\($0.count) items" } ?? "…")
                        LabeledContent("Size", value: folderSummary.map { $0.size.formattedByteCount } ?? "…")
                    } else {
                        LabeledContent("Size", value: "\(item.size.formattedByteCount) (\(item.size.formatted()) bytes)")
                    }
                    if let created = attributes[.creationDate] as? Date {
                        LabeledContent("Created", value: created.formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("Modified", value: item.modified.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Where", value: location)
                }
            }
            .navigationTitle("Info")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                guard item.isDirectory else { return }
                folderSummary = await Self.measure(item.url)
            }
        }
        .presentationDetents([.medium])
    }

    private var attributes: [FileAttributeKey: Any] {
        (try? FileManager.default.attributesOfItem(atPath: item.url.path)) ?? [:]
    }

    private var kind: String {
        if item.isDirectory { return "Folder" }
        if let format = item.format { return "\(format.displayName) archive" }
        return UTType(filenameExtension: item.url.pathExtension)?.localizedDescription ?? "File"
    }

    private var location: String {
        let parent = (item.relativePath as NSString).deletingLastPathComponent
        return parent.isEmpty ? "Zeig" : "Zeig › " + parent.replacingOccurrences(of: "/", with: " › ")
    }

    /// Items and bytes under a folder, counted off the main actor.
    private static func measure(_ url: URL) async -> (count: Int, size: UInt64) {
        await Task.detached(priority: .utility) {
            var count = 0
            var size: UInt64 = 0
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
            while let child = enumerator?.nextObject() as? URL {
                count += 1
                size += UInt64((try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return (count, size)
        }.value
    }
}

// MARK: - Pasteboard

/// Copy and Paste of files, through the system pasteboard (so Files can paste what Zeig
/// copies, and the other way round).
enum FilePasteboard {
    @MainActor
    static var hasFiles: Bool {
        #if canImport(UIKit)
        UIPasteboard.general.itemProviders.contains { $0.hasItemConformingToTypeIdentifier(UTType.item.identifier) && $0.suggestedName != nil }
            || UIPasteboard.general.hasURLs
        #else
        false
        #endif
    }

    @MainActor
    static func copy(_ urls: [URL]) {
        #if canImport(UIKit)
        let providers = urls.compactMap { url -> NSItemProvider? in
            let provider = NSItemProvider(contentsOf: url)
            provider?.suggestedName = url.lastPathComponent
            return provider
        }
        UIPasteboard.general.setItemProviders(providers, localOnly: false, expirationDate: nil)
        ZeigLog.debug("pasteboard", "copied \(urls.count) item(s)")
        #endif
    }

    /// Copies the pasteboard's files into `folder`. Returns the copies.
    @MainActor
    static func paste(into folder: URL, library: FileLibrary) async throws -> [URL] {
        #if canImport(UIKit)
        var sources: [URL] = []
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("Paste-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        for provider in UIPasteboard.general.itemProviders {
            guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .item) == true }) else { continue }
            let name = provider.suggestedName ?? "Pasted Item"
            let url: URL? = try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadFileRepresentation(forTypeIdentifier: type) { file, error in
                    guard let file else {
                        continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                        return
                    }
                    // The loaded file is deleted when this returns: copy it out first.
                    let ext = file.pathExtension
                    let target = scratch.appendingPathComponent(ext.isEmpty || name.hasSuffix("." + ext) ? name : name + "." + ext)
                    do {
                        try FileManager.default.copyItem(at: file, to: target)
                        continuation.resume(returning: target)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            if let url { sources.append(url) }
        }
        return try library.importFiles(sources, into: folder)
        #else
        return []
        #endif
    }
}
