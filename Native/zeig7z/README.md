# zeig7z: the C layer between Swift and 7-Zip

7-Zip is Zeig's main backend. Its code is C++ with a Windows-style COM interface, which Swift
can't call. This folder is a small bridge with a plain C API, `include/zeig7z.h`, that Swift
imports as the `CSevenZip` module. `ZeigBackends/SevenZipBackend.swift` is its only user.

```
Swift (SevenZipBackend) ──C calls──▶ zeig7z.cpp ──COM calls──▶ 7-Zip's format handlers + codecs
                         ◀─callbacks─           ◀─callbacks──
```

| File | What it is |
|---|---|
| `include/zeig7z.h` | The C API. Every function, struct and rule is documented there; read it first. |
| `src/zeig7z.cpp` | The implementation, adapted from 7-Zip's `CPP/7zip/UI/Client7z/Client7z.cpp`. |
| `../scripts/build-7zip.sh` | Compiles 7-Zip and this bridge into `CSevenZip.xcframework`. |
| `../vendor/7zip` | 7-Zip itself (git submodule, pinned to a release tag). |

**License:** 7-Zip is LGPL 2.1+, and this bridge is derived from its sample code, so these two
files are LGPL 2.1+ too (the rest of Zeig is MIT). Keeping the source and build script in the
repository is what lets anyone rebuild the library, as the LGPL requires.

## 7-Zip's API in five minutes

- **Handlers.** Each format (7z, zip, Rar5, Iso, …) is a C++ class registered in a global table
  when the program starts. `GetNumberOfFormats` / `GetHandlerProperty2` read the table: name,
  extensions, whether it can write ("update"), its class ID (a GUID), and how to recognize it
  (a fixed signature, or an `IsArc` function from `GetIsArc`). `CreateObject(classID, interface)`
  makes an instance.
- **Interfaces.** Reading uses `IInArchive`; writing uses `IOutArchive`. They're COM-style:
  reference-counted, created through `CreateObject`, held in `CMyComPtr`.
- **7-Zip pulls, you answer.** You don't feed 7-Zip data. You hand it callback objects, and it
  calls them: "give me the input stream", "give me a password", "here's the next file, give me
  an output stream", "here's how far I am".
- **Properties.** Entry metadata comes from `GetProperty(index, kpidPath / kpidSize / kpidMTime …)`
  as a `PROPVARIANT` (a tagged union). Compression settings go in through
  `ISetProperties::SetProperties` as name/value pairs: the same as the `-m` switches of the
  command line (`x=9`, `m=LZMA2`, `he=on`).
- **Strings.** 7-Zip uses `UString` (wide characters) internally and `FString` for file paths.
  On Apple platforms `FString` is a byte string, and the bridge always fills it with UTF-8
  directly. Never use 7-Zip's `us2fs`/`fs2us` here: they go through the C locale and turn "ä"
  into a Latin-1 byte, so the file isn't found.

## What the bridge does

| C function | 7-Zip calls behind it | Callback classes |
|---|---|---|
| `zeig7z_format_count/at` | `GetNumberOfFormats`, `GetHandlerProperty2`, cached once (`formats()`) | — |
| `zeig7z_open` | picks candidate handlers, `CreateObject(…, IID_IInArchive)`, `IInArchive::Open` | `COpenCallback`: header password; other volumes of a split archive (`IArchiveOpenVolumeCallback`) |
| `zeig7z_entry_count/at` | `GetNumberOfItems`, `GetProperty` | — |
| `zeig7z_get_archive_info` | `GetArchiveProperty` (method, solid, physical size, volumes, comment); for formats that record the method per entry, the largest file's | — |
| `zeig7z_extract`, `zeig7z_test` | `IInArchive::Extract(indices, testMode)` | `CExtractCallback`: creates folders and files, makes paths safe, skips symlinks, restores times and permissions, maps per-file errors |
| `zeig7z_create` | `CreateObject(…, IID_IOutArchive)`, `ISetProperties`, `IOutArchive::UpdateItems` | `CUpdateCallback`: describes each file and opens it for reading |

**Format detection** (`zeig7z_open` with `formats == NULL`), like 7-Zip's own UI: read the
first 64 KB; handlers whose fixed signature matches come first, then those whose `IsArc` says
"yes", then those that say "need more data". Each is tried in turn. With a list of names (Swift
always passes one when it knows the format), only those are tried.

**Safety on extraction.** `sanitizedRelativePath` drops leading `/`, empty, `.` and `..`
components, so an archive can never write outside the destination ("zip slip"). Symbolic links
aren't created at all. Existing files are unlinked before writing, so a planted link can't
redirect the write. Permission bits are kept, but owner read/write is always added.

**Errors.** Every function returns a `zeig7z_result`, and `zeig7z_last_error()` gives the
English detail (thread-local). During extraction the first problem is recorded and the rest of
the files still come out. A data or CRC error on an *encrypted* entry is reported as
`ZEIG7Z_WRONG_PASSWORD`, because 7-Zip can't tell the two apart for most formats.

**Progress and cancelling.** `ProgressRelay` forwards `IProgress::SetTotal/SetCompleted` to the C
callback. A non-zero return makes the bridge answer `E_ABORT`, and 7-Zip unwinds; the result is
`ZEIG7Z_CANCELLED`. A partly written archive is deleted.

## How it's built (and why it's linked the odd way)

`build-7zip.sh` compiles 7-Zip's `Bundles/Format7zF` with its own makefile (the set of handlers
in `7z.so`), adds `FileStreams.cpp` and `zeig7z.cpp`, and then:

1. **Links everything into one object** (`clang -r`). Handlers register themselves from static
   initializers and nothing references them by name. In a normal static library the linker
   would drop every handler as unused, and 7-Zip would know zero formats.
2. **Exports only `zeig7z_*`** (`-exported_symbols_list`). 7-Zip's internal names (CRC tables,
   LZMA functions) become private, so they can't clash with libarchive's copies of the same
   algorithms in the same app.
3. Wraps that object in a static library per slice, then in the xcframework.

The hand-written ARM64 assembly is turned off (`USE_ASM=`). It only speeds up LZMA decoding a
little, and the C versions build everywhere.

## Changing the bridge

1. Edit `zeig7z.h` (document the new function: what it does, ownership, lifetime, errors) and
   `zeig7z.cpp`.
2. `Native/scripts/build-7zip.sh` (about 30 seconds).
3. Use it from `SevenZipBackend.swift`. The header is imported as-is: C structs become Swift
   structs, `const char *` arrives as `UnsafePointer<CChar>`, and C function pointers can't
   capture context (pass a context pointer, as `withCallbacks` does).
4. Add a test in `Packages/ZeigKit/Tests/ZeigBackendsTests`.

Quick C-level experiments without Swift: compile a small C file against
`Packages/ZeigKit/Frameworks/CSevenZip.xcframework/macos-arm64` (`-I…/Headers/CSevenZip`,
link `libCSevenZip.a -lc++`).

## Updating 7-Zip

```bash
git -C Native/vendor/7zip fetch --depth 1 origin tag 26.06   # the new release tag
git -C Native/vendor/7zip checkout 26.06
Native/scripts/build-7zip.sh
swift test --package-path Packages/ZeigKit --scratch-path "$TMPDIR/zeigkit-build"
```

If compiling fails, the makefile's object list (`Bundles/Format7zF/Arc_gcc.mak`) or a COM macro
probably changed. Compare `UI/Client7z/Client7z.cpp` with the old version: the bridge follows it.
`CapabilityTests` will flag a change in which formats 7-Zip can write.

## Not supported yet

- Creating split 7-Zip archives (`GetVolumeSize` says no). RAR splitting goes through rars.
- Opening `.7z.001`-style split sets: 7-Zip's "Split" handler needs a second, nested open.
- Nested archives in one step (a `.tar.gz` opens as one `.tar` here). Compressed tars go to
  libarchive instead, which reads them in one pass.
