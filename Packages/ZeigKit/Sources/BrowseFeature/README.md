# BrowseFeature

The Browse tab: the top of the app's folder. `FolderContent` (ArchiveFeature) shows it, the same
list Recent and every pushed folder use; this view adds the header and the tab's
`NavigationStack`:

- the Photos-style `PageHeader` (title, count and size, + and Settings);
- while selecting, `SelectionHeader` (Select All, count, Done).

Tapping a folder or an archive pushes it (`FolderView`, `ArchiveView`); a folder's chevron
expands it in place. `openRequest` opens files other apps send ("Open in Zeig"), from the top of
the tab's stack.
