# App

The thin app target: `ZeigApp` creates `AppSettings`, `FileLibrary` and `RecentStore` and puts
them in the environment; `RootView` has the three tabs (Browse, Recent, Search in the search
slot), the Settings sheet, and handles "Open in Zeig" (`onOpenURL` → `FileLibrary.adoptOpenedFile`
→ open on Browse). `Info.plist` is generated from `project.yml`.

`AdaptiveTabStyle` picks the sidebar style on iPad and the plain tab bar on iPhone. It goes by
device, not by width, on purpose: the sidebar style already becomes a tab bar in a narrow iPad
window and never shows a sidebar on an iPhone (even an open iPhone Duo), and switching styles
by size class rebuilds the `TabView`, which loses every tab's navigation when the Duo folds.
