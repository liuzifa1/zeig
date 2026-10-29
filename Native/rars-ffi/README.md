# rars-ffi: the RAR backend's Rust ↔ Swift bridge

This crate (`zeig-rars`) wraps [rars](https://github.com/bitplane/rars) — an independent,
Apache-2.0 implementation of the RAR format in Rust — and exposes a small API to Swift with
[UniFFI](https://mozilla.github.io/uniffi-rs/). Zeig uses it as the **experimental** RAR backend:
off by default, and everything it writes is checked by 7-Zip (see the root README).

You don't write any C or any Swift glue here. You write ordinary Rust, mark what Swift should
see, and UniFFI generates the rest.

## The pipeline

```
src/lib.rs ──cargo build──▶ libzeig_rars.a  (one per slice: iOS, simulator, Mac)
     │                            │
     │ #[uniffi::export] etc.     │ uniffi-bindgen reads the interface back out of the
     │ embed interface metadata   │ compiled Mac library ("library mode")
     ▼                            ▼
                         ZeigRars.swift        Swift API (structs, enums, functions)
                         ZeigRarsFFI.h         the C functions the Swift calls
                         ZeigRarsFFI.modulemap makes the header a Clang module
                                  │
                                  ▼
  Packages/ZeigKit/Frameworks/ZeigRarsFFI.xcframework   (static libs + header + module map)
  Packages/ZeigKit/Sources/ZeigRars/ZeigRars.swift      (checked in, marked GENERATED)
                                  │
                                  ▼
  ZeigBackends/RarsBackend.swift: `import ZeigRars`, calls createArchive(…), listEntries(…)
```

`Native/scripts/build-rars.sh` runs all of it. Never edit `ZeigRars.swift` by hand: it's
overwritten on every build.

## What's in this folder

| File | What it is |
|---|---|
| `Cargo.toml` | The crate. `rars` is pinned exactly (`=0.12.3`); `crate-type` builds a static library (for the app) and a dynamic one (for the binding generator). The release profile turns off stripping — see "Gotchas". |
| `src/lib.rs` | Everything Swift sees, with a table at the top mapping each Rust item to its Swift name. |
| `src/bin/uniffi-bindgen.rs` | UniFFI's binding generator, built from this crate so its version always matches the library. |
| `uniffi.toml` | Names of the generated Swift module (`ZeigRars`) and C module (`ZeigRarsFFI`). |

## How Rust items become Swift

| Rust | Swift | Notes |
|---|---|---|
| `#[uniffi::export] pub fn list_entries(path: String, …) -> Result<Vec<RarEntry>, RarError>` | `func listEntries(path: String, …) throws -> [RarEntry]` | snake_case → camelCase. `Result` → `throws`. |
| `#[derive(uniffi::Record)] pub struct RarEntry { … }` | `struct RarEntry` with a memberwise init | Copied across by value. `#[uniffi(default = …)]` gives init defaults. |
| `#[derive(uniffi::Enum)] pub enum RarVersion { Rar29, … }` | `enum RarVersion { case rar29, … }` | |
| `#[derive(uniffi::Error)] pub enum RarError { WrongPassword, Corrupt { message }, … }` | `enum RarError: Error { case WrongPassword; case Corrupt(message:) }` | Case names keep their capital letter. |
| `#[uniffi::export(with_foreign)] pub trait RarProgress { fn report(&self, …) -> bool; }` | `protocol RarProgress` | Swift implements it (`ProgressRelay` in RarsBackend), Rust calls it. |
| `Option<T>`, `Vec<T>`, `String`, `u64`, `bool` | `T?`, `[T]`, `String`, `UInt64`, `Bool` | |
| A Rust `panic!` | a thrown Swift error | Only because panics unwind (the default). Don't set `panic = "abort"`. |

The calls block. `RarsBackend` is only ever called from a background task (`ArchiveService`).

## Try it: add a function

Say you want Swift to ask rars whether a file is a RAR archive at all.

1. **Rust.** In `src/lib.rs`:

   ```rust
   /// Whether `path` starts with a RAR signature (any version).
   #[uniffi::export]
   pub fn is_rar(path: String) -> bool {
       std::fs::read(&path)
           .map(|bytes| ArchiveReader::detect(&bytes).is_ok())
           .unwrap_or(false)
   }
   ```

2. **Check it compiles** (fast, no cross-compiling):

   ```bash
   CARGO_TARGET_DIR=~/Library/Caches/Zeig/native/cargo cargo check --manifest-path Native/rars-ffi/Cargo.toml
   ```

3. **Test it in Rust.** Add a case to `mod tests` at the bottom of `lib.rs`, then:

   ```bash
   CARGO_TARGET_DIR=~/Library/Caches/Zeig/native/cargo cargo test --manifest-path Native/rars-ffi/Cargo.toml --lib
   ```

4. **Regenerate everything:**

   ```bash
   Native/scripts/build-rars.sh
   ```

   Look at the diff of `Packages/ZeigKit/Sources/ZeigRars/ZeigRars.swift`: there's now a
   `public func isRar(path: String) -> Bool`.

5. **Use it from Swift** in `RarsBackend.swift` (`import ZeigRars` is already there), and add
   a Swift test in `Tests/ZeigBackendsTests`.

Changing an existing signature works the same way. The Swift compiler then points at every
call site that has to change.

## Gotchas

- **Don't strip in the release profile.** Release builds strip debug info by default, and on
  macOS 27 stripping the proc-macro dylibs Cargo builds for itself makes them unloadable
  ("mis-aligned LINKEDIT string pool"). `Cargo.toml` sets `strip = "none"`. The build script
  strips the copied static libraries instead (70 MB → 15 MB per slice).
- **`cargo` output goes to `~/Library/Caches/Zeig/native/cargo`** (`CARGO_TARGET_DIR`), never
  `target/` in the repo, which lives in an iCloud-synced folder.
- **First build takes ~8 minutes** (LTO, three targets). Later ones take seconds to a couple of
  minutes. `cargo check` is the quick loop.
- **Paths are UTF-8 Strings.** Fine on Apple platforms. rars itself works with raw bytes for
  names; `decoded_name` turns a stored name into display bytes.
- **rars' API changes between minor versions.** That's why it's pinned with `=`. To update:
  bump the version, run `cargo check`, fix what broke, run the Rust and Swift tests, and the RAR
  fixture tests (`Native/scripts/make-rar-fixtures.sh`).

## Known rars limitations (as of 0.12.3)

Found by Zeig's tests; Zeig works around or flags each one.

| Limitation | What Zeig does |
|---|---|
| `Builder::add_path` adds the files under a folder but not the folders, so empty folders vanish. | `add_directories` adds every folder explicitly first. |
| RAR 2.9 output stores non-ASCII names as raw UTF-8 without RAR's Unicode name field, so other readers show them garbled. | `ArchiveService.verifyWithSevenZip` compares names and reports the check as failed; the user is told. |
| Extraction is all-or-nothing. | `RarsBackend.extract(entries:)` extracts to a scratch folder and moves the chosen files. |
| Volume splitting is RAR 5/7 only. | The option is ignored for RAR 2.9 (`RarsBackend.options`). |

## Where rars comes from

rars is Apache-2.0 and calls itself an independent implementation; it publishes its own format
notes at [bitplane/rar-research](https://github.com/bitplane/rar-research). Its README doesn't
describe how the format knowledge was gathered. Zeig relies on its license and keeps it apart
from 7-Zip's RAR decoder, which comes under the unRAR license restriction (it may not be used to
re-create the RAR compressor). See Settings → Open Source Acknowledgements.
