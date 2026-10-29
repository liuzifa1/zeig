# ZeigCore

What Zeig knows about archives, with no UI and no native code: Foundation only, so it's quick
to test and every other module can use it.

## Main types

| Type | Purpose |
|---|---|
| `ArchiveFormat` | Every format Zeig names: display name, extensions, single-file or not, password support, the common four. |
| `FormatDetector` | Format from the first bytes (signatures), with the name only breaking ties (gzip vs tar.gz). |
| `BackendCapabilities` | **Tune here:** what each engine reads and writes *as Zeig uses it*. `CapabilityTests` checks them against the real libraries. |
| `BackendRouter` | **The routing rule** (see its doc comment and the root README), plus the fallback engine and the creatable formats in display order. |
| `RoutingSettings` | The two experimental switches the router needs. |
| `ArchiveBackend` | The protocol the three engines implement: list, extract, test, create. Blocking. |
| `ArchiveEntry`, `ArchiveListing` | One item in an archive (with `sanitizedPath`), and what opening found. |
| `ArchiveContents`, `ArchiveInfo`, `ArchiveStatistics` | What a backend's `list` returns: entries plus what the engine knows about the whole (format name, method, solid, size, volumes, comment); counts, sizes and ratio for the Info sheet. |
| `ArchiveError` | Every engine's errors mapped to one set, with a user message, a detail and `allowsFallback`. |
| `ArchiveProgress` | Progress callback; return `false` to cancel. (Not `ProgressReporter`: Foundation has one.) |
| `CompressionLevel` | Store … Ultra, mapped onto each engine's scale. |
| `PackRequest` | Everything needed to create an archive. `value(_:)` falls back to option defaults. |
| `FormatOptions`, `FormatOption` | **Add advanced settings here:** per-format options with a one-line summary and a guide topic. |
| `GuideTopic` | The full explanations (Format Guide, ⓘ buttons). |
| `ArchiveTree` | An archive's flat entry list as folders (implicit folders included), for browsing and extracting a folder. |
| `ZeigLog`, `NativeOutputCapture` | The developer console's log (thread-safe ring buffer, also sent to the unified log), and copying stdout/stderr into it. |
| `FileNaming` | "name 2.ext", compound extensions, archive names, extraction folders. |

## Extending

- **New format:** add a case to `ArchiveFormat` (with extensions), a signature in
  `FormatDetector` if it has one, the format to `BackendCapabilities` for the engine(s) that
  handle it, and handler names in `SevenZipBackend.handlerNames` or the writer setup in
  `LibArchiveBackend.configure`. The router needs no change. Add it to the router tests.
- **New advanced setting:** see `FormatOptions`' doc comment.
