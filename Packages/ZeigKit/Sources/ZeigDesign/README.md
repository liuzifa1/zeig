# ZeigDesign

Shared look and small components.

| Type | Purpose |
|---|---|
| `PageHeader`, `PageHeaderIcon`, `BackButton`, `.pageHeader`, `.pinnedTopBar`, `.softTopScrollEdge`, `.pageHeaderControl(in:)` | The Photos-style header, copied unchanged from HNReader (see `PageHeader.swift`'s doc comments). |
| `hnGlass(in:)`, `hnGlassContainer()`, `hnGlassButtonStyle()` | Liquid Glass with pre-26 fallbacks, from HNReader. Never call `glassEffect` directly. |
| `ScopeSwitcher` | Photos' sliding switch (Search's All Files \| Archives). |
| `LargeTitleItem` | A never-collapsing large title as a toolbar item (Search). |
| `FileIcon`, `FileSymbol` | Icon tiles: folders blue, archives orange, other files by type. |
| `ExperimentalBadge` | The orange tag on anything rars does. |
| `OperationModel`, `OperationOverlay` | Progress and Cancel for long operations. The backend thread writes into a lock; the overlay polls, so the main actor isn't flooded. |
| `ShowSettingsAction` (`\.showSettings`) | Opens Settings from any tab's header. |
| `inlineNavigationTitle()` | Inline title on iOS, nothing on macOS (where this package only builds for tests). |
| `FileThumbnail` | Quick Look thumbnails for files (cached in memory), the `FileIcon` tile for folders and archives. |
| `FontTheme`, `FontRole`, `FontFace`, `\.fontTheme` | The Font Lab's roles (title, file name, subtitle, indicator, guide), each with a face and a size. Views ask `fonts.font(.role)`. |
| `ConsoleView`, `ShowConsoleAction` (`\.showConsole`), `logExporter(isPresented:)` | The full developer console as a sheet (live log, search, level filter, share, export, clear), opened from the Browse/Recent headers and Settings → Developer. |
| `ConsolePictureInPicture` | The console's latest lines in the system picture-in-picture window, drawn as video frames into an `AVSampleBufferDisplayLayer` (PiP only plays video). Display only; its "back to app" button opens `ConsoleView`. Needs the `audio` background mode and a real device: the Simulator reports PiP as unsupported. |
| `hidesTabBar(_:)` | Hides the tab bar through UIKit while the selection toolbar is up. SwiftUI's `.toolbar(.hidden, for: .tabBar)` breaks the Search tab's field on 26+. |
