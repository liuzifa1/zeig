# BrowseFeature

The Browse tab, navigated in place like the Files app. `FolderContent` (ArchiveFeature) shows
the current folder; this view adds the header and the tab's `NavigationStack` (for archives):

- at the top with no history, the Photos-style `PageHeader` (title, count and size, + and
  Settings);
- after moving around, `HistoryButtons` (back/forward capsule) on the controls' row with the
  folder's name as the large title under it;
- while selecting, `SelectionHeader` (Select All, count, Done).

`openRequest` opens files other apps send ("Open in Zeig").
