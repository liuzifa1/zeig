# RecentFeature

The Recent tab: `RecentStore` entries grouped Today / Yesterday / This Week / Earlier
(`RecentDay` in ZeigStore), under the same header as Browse. Entries whose file is gone are
pruned on appear.

The list is `FolderContent` with `FolderModel.recent()`, so Recent has everything Browse has:
the long-press menu, swipe to delete, selecting with the toolbar, folders that push on tap and
expand with their chevron, and the + menu (import, paste, new folder, select). New and imported
things go to the top of the library and join the list. Recent adds:

- **Remove from Recent** (`extraSelectionAction`): in the long-press menu, the toolbar's ⋯ and
  as the full swipe. It only takes files off the list; Delete deletes them. Items shown under
  an expanded folder aren't entries, so they don't get it.
- **Clear Recent** in the + menu, after a confirmation.

A selection can span folders, so Compress puts the archive in their shared folder, or at the
top of the library.
