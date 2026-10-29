# App

The thin app target: `ZeigApp` creates `AppSettings`, `FileLibrary` and `RecentStore` and puts
them in the environment; `RootView` has the three tabs (Browse, Recent, Search in the search
slot), the Settings sheet, and handles "Open in Zeig" (`onOpenURL` → `FileLibrary.adoptOpenedFile`
→ open on Browse). `Info.plist` is generated from `project.yml`.
