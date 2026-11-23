# ArchiveFeature

The screens every tab can push, and the actions on files and archives.

| Type | Purpose |
|---|---|
| `LibraryRoute`, `LibraryDestination`, `LibraryOpen` | Folder and archive screens any list can push (`navigationDestination(item:)` with `LibraryDestination`); what a tap does. An archive's Open Extracted replaces the archive screen with the extracted folder, with the folder it's in as the page under it (`LibraryRoute.extracted`, `.folderShowing`). |
| `FolderModel` | A list's state: the folder (or Recent, `FolderModel.recent()`, rows grouped by day with "Opened 2 hours ago" details), folders expanded inline, the selection, what opening an item does (folders and archives push), delete and new folder with items, the sheets it shows, and an extra action for the list's own items (Recent's Remove from Recent). |
| `fileActions(model:folder:)` | The modifier that makes a `FolderModel` work on any `List`: edit mode, the selection toolbar, Compress, Get Info, Rename, Move, Quick Look, pushes, and archive progress and alerts. `FolderContent` uses it. |
| `FolderContent`, `FolderView`, `AddMenu`, `FileRow` | The Files-style list: tap opens (`primaryAction`), long-press shows `FileMenu`, two-finger drag selects, chevrons expand folders, swipe deletes. Browse and Recent show `FolderContent` under their headers; every folder tapped pushes `FolderView` (Search's too). |
| `FileMenu`, `SelectionToolbar`, `SelectionHeader` | The long-press menu (Copy · Move · Share, Quick Look, Open In, Get Info, Rename, Extract/Compress, Duplicate, New Folder with Items, Delete); the selection toolbar, which takes the tab bar's place (Extract, Compress, Move, Delete, then ⋯ with Share, Copy N Items, New Folder with Items; Delete doesn't ask, here or anywhere: `FolderModel.delete`); and the selection header. |
| `FileInfoSheet`, `FilePasteboard` | Get Info, and Copy/Paste through the system pasteboard. Move uses the system's move sheet (`fileMover` in `fileActions`), which can also move files out of the app's folder; Recent follows the files or drops them. |
| `ArchiveView` | An archive's contents as folders (`ArchiveTree` in ZeigCore), preview by tap, extract one item by long-press, Test, Info. **Extract All** (`ExtractAllButton`) has its own `ArchiveActions` without the overlay: while extracting it's a stop button with a progress ring, then Open Extracted. |
| `ArchiveActions` (`.archiveActions(_:showsProgress:)`) | Open / extract / test with password prompt-and-retry, progress overlay (unless the control shows progress itself), error alerts, Recent. Several archives extract one after another (`extract(_ urls:)`): they share one progress card and password prompt. |
| `PackSheet` | The create sheet: name, format, level, password (with an eye icon to show or hide it), advanced settings on their own pushed page (`PackAdvancedSettings`), explanations and ⓘ guide links, RAR warnings, and the result of the rars check. |
| `FormatGuideView`, `GuideTopicView` | The full explanations (Settings and ⓘ). |

Adding a file action: put it in `FileMenu` (and `SelectionToolbar` for selections) and, if it runs an archive
operation, in `ArchiveActions` so it gets the password prompt, progress and alerts for free.
