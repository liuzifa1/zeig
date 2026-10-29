# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, Cursor, …) working in this repository.
`CLAUDE.md` just includes this file. Humans: see `README.md`.

## What this is

A native archive app for iPhone and iPad (iOS 18+), in Swift 6 and SwiftUI, with Liquid Glass on
26+. It opens and creates many archive formats with three native engines: **7-Zip** (main),
**libarchive** (the formats 7-Zip can't create) and **rars** (experimental RAR creation, opt-in).
One thin app target; everything else is in the local package `Packages/ZeigKit` (one target per
module), plus the native code under `Native/`.

## Commands

```bash
Native/scripts/build-all.sh              # once after cloning, and after any change under Native/
xcodegen generate                        # after changing project.yml or adding/removing files under App/
xcodebuild -project Zeig.xcodeproj -scheme Zeig -destination 'generic/platform=iOS Simulator' build
swift test --package-path Packages/ZeigKit --scratch-path "$TMPDIR/zeigkit-build"
CARGO_TARGET_DIR=~/Library/Caches/Zeig/native/cargo cargo test --manifest-path Native/rars-ffi/Cargo.toml --lib
```

- The checkout lives in an iCloud-synced folder. **Never** put build output inside the repo
  (`-derivedDataPath ./build`, a plain `swift build` without `--scratch-path`, Cargo's `target/`):
  iCloud tags the files and code signing fails. Native intermediates go to
  `~/Library/Caches/Zeig/native` (the scripts do this).
- Before finishing a change: build the app for the simulator and run the package tests. After
  touching `Native/rars-ffi`, also run `cargo test` and `Native/scripts/build-rars.sh`.
- Don't run `-allowProvisioningUpdates` without asking: it changes the owner's developer account.

## Module map

| Module | Owns | May import |
|---|---|---|
| `ZeigCore` | `ArchiveFormat`, `FormatDetector`, `BackendRouter` + `BackendCapabilities` (the routing rule), `ArchiveBackend` protocol, `ArchiveEntry`, `ArchiveContents`/`ArchiveInfo`/`ArchiveStatistics`, `ArchiveError`, `PackRequest`, `FormatOptions` (advanced settings), `GuideTopic` (explanations), `ArchiveTree`, `FileNaming`, `ZeigLog` (developer console log), `NativeOutputCapture` | Foundation |
| `ZeigBackends` | `SevenZipBackend`, `LibArchiveBackend`, `RarsBackend`, `ArchiveService` (routing, fallback, background work, rars check) | ZeigCore, CSevenZip, CLibArchive, ZeigRars |
| `ZeigRars` | UniFFI's **generated** Swift for rars. Never edit; run `build-rars.sh`. | ZeigRarsFFI |
| `ZeigStore` | `AppSettings`, `FileLibrary` (the app folder), `RecentStore` | ZeigCore |
| `ZeigDesign` | `PageHeader`, glass helpers (from HNReader), `ScopeSwitcher`, `LargeTitleItem`, `FileIcon`, `FileThumbnail`, `ExperimentalBadge`, `OperationModel`/`OperationOverlay`, `FontTheme` (Font Lab roles), `ConsoleView` + `ConsolePictureInPicture` (developer console), `hidesTabBar`, `showSettings`/`showConsole` | ZeigCore |
| `ArchiveFeature` | Screens every tab pushes: `FolderModel`/`FolderContent`/`FolderView` (Files-style list), `FileMenu`, `SelectionToolbar`/`SelectionHeader`, `FileInfoSheet`, `FilePasteboard`, `ArchiveView`, `PackSheet`, guide views, `ArchiveActions`, `LibraryRoute` | ZeigCore, ZeigBackends, ZeigStore, ZeigDesign |
| `BrowseFeature` / `RecentFeature` / `SearchFeature` | One tab each | the above + ArchiveFeature |
| `SettingsFeature` | Settings sheet, Backends, Developer (console, Font Lab), About / Privacy / Open Source | the above + ArchiveFeature |
| `App/` | Entry point, tabs, "Open in Zeig" | everything |
| `CSevenZip`, `CLibArchive`, `ZeigRarsFFI` | Binary targets built by `Native/scripts` | — |

Dependencies only point downwards. Feature modules don't import each other (except
ArchiveFeature, as listed). `Package.swift` is the source of truth; keep this table in sync.

## Conventions

- **Swift 6 strict concurrency.** Stores and view models are `@MainActor @Observable final class`.
  Backends are `Sendable` structs whose methods block; only `ArchiveService` calls them, from a
  detached task (`background`). Don't silence isolation errors with `@unchecked Sendable` or
  `nonisolated(unsafe)` unless a comment says why.
- **Typed throws for archive work:** backends and the service throw `ArchiveError`. Use
  `do throws(ArchiveError)` so `catch` blocks keep the type.
- **Routing lives in one place**: `BackendRouter` (rule) and `BackendCapabilities` (tables).
  Never choose a backend at a call site. `CapabilityTests` keeps the tables honest.
- **Views never call a backend directly.** They use `ArchiveService` through `ArchiveActions`
  (open, extract, test with password prompt and progress) or, in the create sheet, `create`.
- **Files stay in the app folder.** `FileLibrary` is the only code that copies files in
  (`importFiles`, `adoptOpenedFile`); archives extract next to themselves. No security-scoped
  bookmarks anywhere else.
- **Advanced settings:** add a `FormatOption` in `FormatOptions` (stable `id`, one-line
  `summary`, a `guide` topic), read it with `request.value(id)` in the backend that creates the
  format, and add or reuse a `GuideTopic`. `everyOptionHasAGuideTopic` enforces the last part.
- **The experimental backend stays fenced off:** rars is used only when the user turned it on,
  every archive it writes goes through `ArchiveService.verifyWithSevenZip`, and anything showing
  it carries `ExperimentalBadge` or a warning.
- **Headers:** Browse and Recent use `PageHeader` (`.pageHeader { … }`, which hides the
  navigation bar) with + and Settings at the top right. Pushed screens use the system bar with
  `.softTopScrollEdge()` or `.pinnedTopBar { … }`. Search keeps the system bar, with its title
  as a leading toolbar item (`LargeTitleItem`) and the switch in `.pinnedTopBar`.
- **Search field:** on iOS 26+ `.searchable` goes on `SearchView`'s NavigationStack, never on the
  `TabView` (that breaks the other tabs' list bounce). See `SearchSession`.
- **Liquid Glass:** for custom controls use `hnGlass(in:)`, `pageHeaderControl(in:)`,
  `hnGlassContainer()`. Never call `glassEffect` directly: the helpers carry the pre-26 fallback.
- **File lists work like Files:** `List(selection:)` with
  `.contextMenu(forSelectionType:menu:primaryAction:)`. The primary action opens (tap), the menu
  is the long-press menu, and the selection binding gives two-finger drag selection. While
  selecting, `SelectionToolbar` (a `.bottomBar` toolbar) replaces the tab bar. Moving goes
  through the system's move sheet (`fileMover`). Don't put
  `Button`s or `NavigationLink`s in rows: a `Button` row takes the long press and the menu never
  appears. Selecting is the list's edit mode, mirrored by `FolderModel.isSelecting`.
- **Swipe actions that ask first don't use `role: .destructive`**: that role removes the row at
  once, and removing it again after the confirmation crashes the list ("invalid number of
  items"). Use `.tint(.red)`. A destructive role is fine only when the data goes immediately.
  Deleting files never asks (`FolderModel.delete`, like Files), so the file list's swipe uses it.
- **Fonts:** text in lists, headers and guides uses `@Environment(\.fontTheme)`
  (`fonts.font(.fileName)`, `.title`, `.subtitle`, `.indicator`, `.guide`) so the Font Lab applies
  everywhere. The theme is set at the app's root so sheets get it too.
- **Logging:** engines and the router log through `ZeigLog` (shown by the developer console).
  Log decisions, timings and errors; never passwords or file contents.
- **UI text:** sentence case, short, plain. Say what happens, not how it works.
- **Accessibility:** every icon-only button gets an `accessibilityLabel`.

## Native code

- `Native/zeig7z` (C/C++, LGPL like 7-Zip) and `Native/rars-ffi` (Rust + UniFFI) each have a
  README with the full workflow. `docs/native-builds.md` covers the build scripts.
- 7-Zip paths: UTF-8 straight into `FString`; never `us2fs`/`fs2us`.
- libarchive calls run inside `withUTF8Locale`.
- Keep `zeig7z.h` fully documented: ownership and lifetime of every pointer, error behavior.

## Documentation rules

- Every public type gets a doc comment saying what it's for and any non-obvious constraint.
  Comments explain *why*, not what the next line does.
- Each module folder has a `README.md`: what it owns, its main types, how to extend it. Update
  it in the same change as the code.
- Behavior the user can see (formats, limits, defaults) is documented in the root README.

## Tests

Swift Testing (`import Testing`) in `Packages/ZeigKit/Tests`:

- `ZeigCoreTests`: routing rule (format by format), detection, naming, option mapping.
- `ZeigStoreTests`: library, Recent, settings (temporary folders, in-memory stores).
- `ZeigBackendsTests`: real round trips through all three libraries for every creatable format,
  passwords, zip-slip, cancellation, cross-reading between backends, capability tables, and
  `RarFixtureTests` (archives made by RARLAB's rar; run `Native/scripts/make-rar-fixtures.sh`).

Logic and backend behavior must have tests. A bug found in a backend gets a test that reproduces
it, and a `differences(…)` message so failures say what differs.

## Gotchas

- Foundation has its own `ProgressReporter` (26 SDKs); ours is `ArchiveProgress`.
- Several `.alert`s on one view work, but the Simulator's screenshots lag behind: wait before
  concluding one didn't show. Simulator taps on a `Toggle` sometimes need a short hold.
- `ArchiveEntry.index` is the backend's index. Pass entries back to the same backend
  (`ArchiveListing.backend`) that listed them.
- Single-file formats (gzip, xz, zstd, …) take exactly one file; `PackSheet` prevents anything else.
- `.environment` modifiers apply inward only: a `.sheet` attached outside one doesn't see it.
- `PageHeader`'s title has `minimumScaleFactor(0.6)`; give short root titles `.fixedSize()` or they
  shrink next to the controls.
- The console's picture-in-picture window is video (`ConsolePictureInPicture` draws the log into
  frames). The Simulator reports PiP as unsupported, so the option is hidden there: test it on a
  device. It needs `UIBackgroundModes: audio` in `project.yml`.
- Hide the tab bar with `hidesTabBar(_:)` (UIKit), never `.toolbar(.hidden, for: .tabBar)`, which
  breaks the Search tab's field on 26+. `.bottomBar` toolbars don't exist on macOS, where the
  package builds for tests: keep them behind `#if os(iOS)`.

## Don't

- Don't add third-party Swift packages, or new native libraries, without asking.
- Don't commit the generated `.xcodeproj`, `App/Info.plist` or `Packages/ZeigKit/Frameworks`.
- Don't edit `Sources/ZeigRars/ZeigRars.swift` by hand.
- Don't change the bundle ID (`top.kitsune.zeig`) or team ID without asking.
- Don't make rars the default for anything.
