import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import ZeigBackends
import ZeigCore
import ZeigDesign
import ZeigStore

/// A folder pushed from Recent or Search: the system navigation bar with the folder's name,
/// + in the toolbar, and Select / Select All / Done while selecting. Subfolders push too.
/// (Browse shows the same list with in-place navigation under its own header.)
public struct FolderView: View {
    @State private var model: FolderModel

    public init(folder: URL) {
        _model = State(initialValue: FolderModel(folder: folder))
    }

    public var body: some View {
        FolderContent(model: model)
            .navigationTitle(model.isSelecting ? selectionTitle : model.title)
            .inlineNavigationTitle()
            .softTopScrollEdge()
            .toolbar {
                if model.isSelecting {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(model.allSelected ? "Deselect All" : "Select All") { model.toggleSelectAll() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") { model.isSelecting = false }
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        AddMenu(model: model) { Image(systemName: "plus") }
                    }
                }
            }
    }

    private var selectionTitle: String {
        model.selection.count == 1 ? "1 Item" : "\(model.selection.count) Items"
    }
}

/// The + menu: import, paste, new folder, select. `label` is the button's look (a glass circle
/// in headers, a plain symbol in toolbars).
public struct AddMenu<Label: View>: View {
    let model: FolderModel
    let label: Label
    @Environment(FileLibrary.self) private var library
    @Environment(RecentStore.self) private var recent

    public init(model: FolderModel, @ViewBuilder label: () -> Label) {
        self.model = model
        self.label = label()
    }

    public var body: some View {
        Menu {
            Button("Import from Files…", systemImage: "square.and.arrow.down") { model.isImporting = true }
            if FilePasteboard.hasFiles {
                Button("Paste", systemImage: "doc.on.clipboard") {
                    Task { await paste() }
                }
            }
            Button("New Folder", systemImage: "folder.badge.plus") { model.isCreatingFolder = true }
            Divider()
            Button("Select", systemImage: "checkmark.circle") { model.isSelecting = true }
                .disabled(model.rows.isEmpty)
        } label: {
            label
        }
        .accessibilityLabel("Add")
    }

    private func paste() async {
        do {
            let copies = try await FilePasteboard.paste(into: model.folder ?? library.root, library: library)
            for copy in copies { recent.record(library.relativePath(of: copy), .imported) }
        } catch {
            model.actions.alert = AlertContent(title: "Can't paste", message: error.localizedDescription)
        }
    }
}

/// A folder's list, with everything you can do to its items:
/// - tap opens (folders in place or pushed, archives pushed, other files in Quick Look);
/// - the chevron expands a folder inline;
/// - long-press opens the Files-style menu (`FileMenu`), for one item or the selection;
/// - two-finger drag, Select in the + menu, or Select in the header start selecting; the
///   selection toolbar (`SelectionToolbar`) then takes the tab bar's place;
/// - Move (menu or toolbar) opens the system's move sheet, which can also move files out of
///   the app's folder;
/// - swipe left to delete. Every delete is immediate (`FolderModel.delete`), as in Files.
public struct FolderContent: View {
    @Bindable var model: FolderModel
    /// Browse's root folder shows chevrons to expand folders inline; elsewhere they push.
    var showsDisclosure: Bool
    @Environment(FileLibrary.self) private var library
    @Environment(RecentStore.self) private var recent
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var newName = ""

    public init(model: FolderModel, showsDisclosure: Bool = true) {
        self.model = model
        self.showsDisclosure = showsDisclosure
    }

    private var folderURL: URL { model.folder ?? library.root }
    private var service: ArchiveService { ArchiveService(settings: settings.routing) }

    public var body: some View {
        list
            .overlay {
                if model.rows.isEmpty {
                    ContentUnavailableView {
                        Label("No Files", systemImage: "folder")
                    } description: {
                        Text("Import files with +, or add them in the Files app under On My iPhone › Zeig.")
                    }
                }
            }
            .modifier(SelectionToolbarPlacement(model: model, folder: folderURL))
            .task(id: "\(library.changeCount)|\(model.folder?.path ?? "")") { model.reload(library) }
            .onChange(of: scenePhase) { _, phase in
                // Files may have been added in the Files app meanwhile.
                if phase == .active { model.reload(library) }
            }
            .fileImporter(isPresented: $model.isImporting, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                importFiles(result)
            }
            .sheet(item: $model.packSources) { sources in
                PackSheet(sources: sources) { model.isSelecting = false }
            }
            .sheet(item: $model.infoItem) { FileInfoSheet(item: $0) }
            .alert("New Folder", isPresented: $model.isCreatingFolder) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Create") { createFolder() }
            }
            .alert("Rename", isPresented: Binding(get: { model.renaming != nil }, set: { if !$0 { model.renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { model.renaming = nil }
                Button("Rename") { rename() }
            }
            .alert("Extracted", isPresented: Binding(get: { model.actions.extracted != nil }, set: { if !$0 { model.actions.extracted = nil } })) {
                Button("Show Folder") {
                    if let folder = model.actions.extracted { open(folder: folder) }
                    model.actions.extracted = nil
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("The files are in “\(model.actions.extracted?.lastPathComponent ?? "")”.")
            }
            .navigationDestination(item: $model.pushed) { route in
                switch route {
                case .folder(let url): FolderView(folder: url)
                case .archive(let url): ArchiveView(url: url)
                }
            }
            .quickLookPreview($model.previewURL)
            .archiveActions(model.actions)
    }

    private var list: some View {
        List(selection: $model.selection) {
            ForEach(model.rows) { row in
                FileRow(
                    item: row.item,
                    depth: row.depth,
                    disclosure: showsDisclosure && row.item.isDirectory
                        ? (model.expanded.contains(row.id), {
                            // Animated so the children slide in and out under the folder, as in Files.
                            withAnimation(.snappy(duration: 0.3)) { model.toggleExpanded(row.item, library: library) }
                        })
                        : nil,
                    reservesDisclosureColumn: showsDisclosure
                )
                .tag(row.id)
                .swipeActions {
                    // The destructive role removes the row at once, which matches: the file
                    // goes immediately too.
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        model.delete([row.item], library: library, recent: recent)
                    }
                }
            }
        }
        .listStyle(.plain)
        .contextMenu(forSelectionType: FileItem.ID.self) { ids in
            FileMenu(items: model.items(ids), model: model, folder: folderURL, service: service)
        } primaryAction: { ids in
            guard !model.isSelecting, ids.count == 1, let item = model.items(ids).first else { return }
            model.selection = []
            open(item)
        }
        .modifier(EditModeFromSelection(isSelecting: $model.isSelecting))
        // On the list, not next to `fileImporter`: two file dialogs on one view can block
        // each other.
        .fileMover(
            isPresented: Binding(get: { model.moving != nil }, set: { if !$0 { model.moving = nil } }),
            files: model.moving?.map(\.url) ?? []
        ) { result in
            moved(result)
        }
    }

    private func open(_ item: FileItem) {
        if item.isDirectory {
            open(folder: item.url)
        } else if item.isArchive {
            model.pushed = .archive(item.url)
        } else {
            model.previewURL = item.url
        }
    }

    private func open(folder: URL) {
        if model.navigatesInPlace { model.go(to: folder) } else { model.pushed = .folder(folder) }
    }

    // MARK: Actions

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            let copies = try library.importFiles(try result.get(), into: folderURL)
            for copy in copies { recent.record(library.relativePath(of: copy), .imported) }
        } catch {
            model.actions.alert = AlertContent(title: "Can't import", message: error.localizedDescription)
        }
    }

    private func createFolder() {
        defer { newName = "" }
        do {
            try library.createFolder(named: newName, in: folderURL)
        } catch {
            model.actions.alert = AlertContent(title: "Can't create the folder", message: error.localizedDescription)
        }
    }

    private func rename() {
        guard let item = model.renaming else { return }
        model.renaming = nil
        defer { newName = "" }
        do {
            let renamed = try library.rename(item.url, to: newName)
            recent.move(item.relativePath, to: library.relativePath(of: renamed))
        } catch {
            model.actions.alert = AlertContent(title: "Can't rename", message: error.localizedDescription)
        }
    }

    /// After the system move sheet: keep Recent pointing at the files, or drop the ones that
    /// left the app's folder.
    private func moved(_ result: Result<[URL], Error>) {
        let items = model.moving ?? []
        model.moving = nil
        switch result {
        case .success(let destinations):
            for (item, destination) in zip(items, destinations) {
                if library.isInside(destination) {
                    recent.move(item.relativePath, to: library.relativePath(of: destination))
                } else {
                    recent.remove(item.relativePath)
                }
            }
            ZeigLog.info("files", "moved \(destinations.count) item(s)")
            model.isSelecting = false
            // The move happened outside the library's own methods.
            library.noteChange()
        case .failure(let error):
            model.actions.alert = AlertContent(title: "Can't move", message: error.localizedDescription)
        }
    }
}

/// The selection toolbar at the bottom, in the tab bar's place (as in Files). iOS only: macOS
/// builds this package just for tests.
private struct SelectionToolbarPlacement: ViewModifier {
    let model: FolderModel
    let folder: URL

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .toolbar {
                if model.isSelecting {
                    SelectionToolbar(model: model, folder: folder)
                }
            }
            .hidesTabBar(model.isSelecting)
        #else
        content
        #endif
    }
}

/// Puts the list in edit mode while selecting, and back. The list's two-finger drag sets edit
/// mode itself, which turns `isSelecting` on through the same binding.
private struct EditModeFromSelection: ViewModifier {
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

/// Icon (or thumbnail), name, and size or date. In Browse, folders get a chevron that
/// expands them inline, and rows under expanded folders are indented.
public struct FileRow: View {
    let item: FileItem
    var detail: String?
    var depth: Int
    /// (is expanded, toggle) for folders that can expand inline.
    var disclosure: (Bool, () -> Void)?
    /// Keep the chevron's column for every row (Browse), so file icons line up with folder
    /// icons, as in Files. Lists without chevrons (Recent, Search) leave it out.
    var reservesDisclosureColumn: Bool
    @Environment(\.fontTheme) private var fonts

    public init(
        item: FileItem, detail: String? = nil, depth: Int = 0,
        disclosure: (Bool, () -> Void)? = nil, reservesDisclosureColumn: Bool = false
    ) {
        self.item = item
        self.detail = detail
        self.depth = depth
        self.disclosure = disclosure
        self.reservesDisclosureColumn = reservesDisclosureColumn
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let disclosure {
                let expanded = disclosure.0
                Button(action: disclosure.1) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 22, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(expanded ? "Collapse \(item.name)" : "Expand \(item.name)")
            } else if reservesDisclosureColumn {
                Color.clear.frame(width: 22)
            }
            FileThumbnail(url: item.url, isDirectory: item.isDirectory, format: item.format, modified: item.modified)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(fonts.font(.fileName))
                    .lineLimit(2)
                Text(detail ?? defaultDetail)
                    .font(fonts.font(.subtitle))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 24)
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.2), value: disclosure?.0)
    }

    private var defaultDetail: String {
        let date = item.modified.formatted(date: .abbreviated, time: .shortened)
        return item.isDirectory ? date : "\(item.size.formattedByteCount) · \(date)"
    }
}
