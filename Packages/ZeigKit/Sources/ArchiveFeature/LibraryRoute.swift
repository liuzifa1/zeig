import SwiftUI
import ZeigCore
import ZeigStore

/// Screens any tab can push: a folder of the library, or an archive's contents.
public enum LibraryRoute: Hashable {
    case folder(URL)
    case archive(URL)
    /// A folder with one of its subfolders already pushed on top of it. After Open Extracted,
    /// so the page under the extracted folder is the folder it's in (its "..").
    case folderShowing(URL, child: URL)

    /// Where to go after extracting `extracted` from an archive listed in `listedIn` (`nil`
    /// for a list that isn't a folder: Recent, Search): the extracted folder alone when the
    /// list is already its parent, else the parent with the extracted folder on top.
    public static func extracted(_ extracted: URL, listedIn: URL?) -> LibraryRoute {
        let parent = extracted.deletingLastPathComponent()
        if let listedIn, listedIn.standardizedFileURL.path == parent.standardizedFileURL.path {
            return .folder(extracted)
        }
        return .folderShowing(parent, child: extracted)
    }
}

/// The screen for a pushed `LibraryRoute`. `listedIn` is the folder of the list that pushed it
/// (`nil` for Recent and Search), and `replace` swaps the pushed screen for another route: an
/// archive's Open Extracted replaces the archive with the extracted folder.
public struct LibraryDestination: View {
    let route: LibraryRoute
    let listedIn: URL?
    let replace: (LibraryRoute) -> Void

    public init(_ route: LibraryRoute, listedIn: URL?, replace: @escaping (LibraryRoute) -> Void) {
        self.route = route
        self.listedIn = listedIn
        self.replace = replace
    }

    public var body: some View {
        switch route {
        case .folder(let url):
            FolderView(folder: url)
        case .folderShowing(let url, let child):
            FolderView(folder: url, showing: child)
        case .archive(let url):
            ArchiveView(url: url)
                .environment(\.openExtracted, OpenExtractedAction { folder in
                    replace(.extracted(folder, listedIn: listedIn))
                })
        }
    }
}

/// Lets an archive screen hand its extracted folder to the screen that pushed it, which shows
/// the folder in the archive's place (`LibraryDestination`). `nil` when nothing pushed it.
public struct OpenExtractedAction {
    let action: @MainActor (URL) -> Void
    @MainActor func callAsFunction(_ folder: URL) { action(folder) }
}

extension EnvironmentValues {
    @Entry var openExtracted: OpenExtractedAction? = nil
}

/// What tapping an item does: folders and archives push, other files open in Quick Look.
public enum LibraryOpen {
    public static func route(for item: FileItem) -> LibraryRoute? {
        if item.isDirectory { return .folder(item.url) }
        if item.isArchive { return .archive(item.url) }
        return nil
    }
}
