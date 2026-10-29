# ArchiveFeature

The screens every tab can push, and the actions on files and archives.

| Type | Purpose |
|---|---|
| `LibraryRoute`, `.libraryDestinations()`, `LibraryOpen` | Folder and archive screens any `NavigationStack` can push; what a tap does. |
| `FolderModel` | A folder screen's state: the folder, back/forward history (`go`, `goBack`, `goForward`), folders expanded inline, the selection, and the sheets it shows. |
| `FolderContent`, `FolderView`, `AddMenu`, `FileRow` | The Files-style list: tap opens (`primaryAction`), long-press shows `FileMenu`, two-finger drag selects, chevrons expand folders, swipe deletes. Browse shows `FolderContent` with in-place navigation; Recent and Search push `FolderView`. |
| `FileMenu`, `SelectionToolbar`, `SelectionHeader` | The long-press menu (Copy · Move · Share, Quick Look, Open In, Get Info, Rename, Extract/Compress, Duplicate, New Folder with Items, Delete); the selection toolbar, which takes the tab bar's place (Extract, Compress, Move, Delete, then ⋯ with Share, Copy N Items, New Folder with Items; Delete doesn't ask, here or anywhere: `FolderModel.delete`); and the selection header. |
| `FileInfoSheet`, `FilePasteboard` | Get Info, and Copy/Paste through the system pasteboard. Move uses the system's move sheet (`fileMover` in `FolderContent`), which can also move files out of the app's folder; Recent follows the files or drops them. |
| `ArchiveView` | An archive's contents as folders (`ArchiveTree` in ZeigCore), preview by tap, extract one item by long-press, Extract All, Test, Info. |
| `ArchiveActions` (`.archiveActions(_:)`) | Open / extract / test with password prompt-and-retry, progress overlay, error alerts, Recent. |
| `PackSheet` | The create sheet: name, format, level, password, advanced settings with explanations and ⓘ guide links, RAR warnings, and the result of the rars check. |
| `FormatGuideView`, `GuideTopicView` | The full explanations (Settings and ⓘ). |

Adding a file action: put it in `FileMenu` (and `SelectionToolbar` for selections) and, if it runs an archive
operation, in `ArchiveActions` so it gets the password prompt, progress and alerts for free.
