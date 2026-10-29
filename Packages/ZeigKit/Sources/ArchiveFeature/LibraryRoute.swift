import SwiftUI
import ZeigCore
import ZeigStore

/// Screens any tab can push: a folder of the library, or an archive's contents.
public enum LibraryRoute: Hashable {
    case folder(URL)
    case archive(URL)
}

public extension View {
    /// Registers the `LibraryRoute` screens on a tab's `NavigationStack`.
    func libraryDestinations() -> some View {
        navigationDestination(for: LibraryRoute.self) { route in
            switch route {
            case .folder(let url): FolderView(folder: url)
            case .archive(let url): ArchiveView(url: url)
            }
        }
    }
}

/// What tapping an item does: folders and archives push, other files open in Quick Look.
public enum LibraryOpen {
    public static func route(for item: FileItem) -> LibraryRoute? {
        if item.isDirectory { return .folder(item.url) }
        if item.isArchive { return .archive(item.url) }
        return nil
    }
}
