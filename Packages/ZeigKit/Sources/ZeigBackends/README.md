# ZeigBackends

The three engines behind `ArchiveBackend`, and `ArchiveService`, the one thing the UI calls.

## Main types

| Type | Purpose |
|---|---|
| `ArchiveService` | Routes through `BackendRouter`, falls back to the other engine when a file won't open, runs the blocking work on a detached task (`background`), extracts into new folders next to archives, and has 7-Zip check everything rars writes (`verifyWithSevenZip`). |
| `SevenZipBackend` | 7-Zip through the C bridge (`CSevenZip`, `Native/zeig7z`). Maps formats to 7-Zip handler names and `PackRequest`s to `-m` properties (`properties(for:)`). |
| `LibArchiveBackend` | libarchive's C API directly (`CLibArchive`). Streams; one pass per operation. Runs under a per-thread UTF-8 locale (`withUTF8Locale`). |
| `RarsBackend` | rars through UniFFI (`ZeigRars`). Experimental. Maps options in `options(for:)`. |
| `SourceWalker` | Lists files for libarchive the same way 7-Zip and rars name them. |

## Rules

- Backends block and are `Sendable` structs; never call them on the main actor. Go through
  `ArchiveService`.
- Every backend sanitizes entry paths when extracting (nothing outside the destination), skips
  symbolic links, and deletes a partly written archive when creation fails or is cancelled.
- Map engine errors to `ArchiveError` at the edge (`check`, `readError`, `call`).
- A bug found in an engine gets a test in `Tests/ZeigBackendsTests`.

## Adding an operation

Add it to `ArchiveBackend` in ZeigCore, implement it in all three backends (or throw
`.readOnlyFormat` / `.other` where an engine can't), expose it on `ArchiveService` with
`background { … }`, and test it with real archives.
