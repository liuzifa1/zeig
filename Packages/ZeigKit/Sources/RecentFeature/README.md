# RecentFeature

The Recent tab: `RecentStore` entries grouped Today / Yesterday / This Week / Earlier, under the
same header as Browse. Its + menu imports files, starts selecting, or clears the list. Entries
whose file is gone are pruned on appear.

Selecting works as in Browse: `RecentView` keeps a `FolderModel` showing these items
(`show(_:)`) and attaches `fileActions`, so it gets the same header, toolbar and sheets. The
toolbar acts on the files themselves, so its Delete deletes them; ⋯ adds Remove from Recent
(`extraSelectionAction`), which only takes them off the list. A selection can span folders, so
Compress puts the archive in their shared folder, or at the top of the library.

 `RecentView.sections` does the grouping (pure, testable).
