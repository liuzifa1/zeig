# ZeigStore

Persistent state, all `@MainActor @Observable`, shared through the SwiftUI environment.

| Type | Purpose |
|---|---|
| `AppSettings` | UserDefaults-backed settings: the experimental RAR switches (`routing`), default format and level, the last advanced settings per format, developer mode (console, native output capture) and the Font Lab's choices. |
| `FileLibrary` | The app's Documents folder: listing, search (`allItems`), importing (copies in, coordinated for iCloud and other providers), "Open in Zeig" (`adoptOpenedFile` empties the Inbox), new folder, rename, delete, move, duplicate, new folder with items, all folders (for Move). `changeCount` goes up on every change; views reload on it. |
| `RecentStore` | The Recent list as JSON in Application Support: newest action per file, relative paths (survive container moves), `prune`, `move` after renames. |
| `FileItem` | A file or folder in the library, with its detected format. |

Zeig never touches files outside `FileLibrary.root`; that's why nothing here needs
security-scoped bookmarks.
