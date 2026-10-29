# Native builds

Zeig's archive engines are C, C++ and Rust libraries built from source into static
`.xcframework`s, which `Packages/ZeigKit/Package.swift` uses as binary targets. Nothing
prebuilt is downloaded and nothing built is checked in.

```
Native/
├── vendor/            git submodules, each pinned to a release tag
│   ├── 7zip           7-Zip 26.05            (ip7z/7zip)
│   ├── libarchive     libarchive 3.8.10
│   ├── xz             XZ Utils 5.8.4         (liblzma for libarchive)
│   ├── zstd           Zstandard 1.5.7
│   └── lz4            LZ4 1.10.0
├── zeig7z/            Zeig's C bridge to 7-Zip           → README.md there
├── rars-ffi/          Zeig's Rust crate around rars       → README.md there
├── fixtures/          (git-ignored) your inputs for make-rar-fixtures.sh
└── scripts/
    ├── common.sh            shared settings: slices, paths, cmake_install, make_xcframework
    ├── build-all.sh         all of the below, with prerequisite checks
    ├── build-libarchive.sh  → CLibArchive.xcframework
    ├── build-7zip.sh        → CSevenZip.xcframework
    ├── build-rars.sh        → ZeigRarsFFI.xcframework + Sources/ZeigRars/ZeigRars.swift
    └── make-rar-fixtures.sh real RAR test archives, made with RARLAB's rar
```

## Prerequisites

```bash
brew install cmake xcodegen
```

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin
```

```bash
git submodule update --init
```

Then:

```bash
Native/scripts/build-all.sh
```

## Slices

Every library is built three times:

| Slice | Target | Why |
|---|---|---|
| `ios` | arm64, iPhoneOS SDK, iOS 18 | devices |
| `iossim` | arm64, iPhoneSimulator SDK | Apple-silicon simulators (Intel simulators aren't built, and `project.yml` excludes `x86_64`) |
| `macos` | arm64, macOS 15 | only so `swift test` can run the backend tests on the Mac, in seconds |

## Where things go

- **Intermediates:** `~/Library/Caches/Zeig/native` (override with `ZEIG_NATIVE_BUILD`). Object
  files, CMake trees and Cargo's `target` never go into the repo: it lives in an iCloud-synced
  folder, and iCloud tags build products, which breaks code signing.
- **Results:** `Packages/ZeigKit/Frameworks/*.xcframework` (git-ignored).

## Things that look odd but are on purpose

| What | Why |
|---|---|
| Each framework's headers sit in `Headers/<ModuleName>/`, not `Headers/` | SwiftPM copies the headers of all static-library frameworks into one `include/` folder, so three `module.modulemap` files would overwrite each other ("Multiple commands produce …/module.modulemap"). In a folder named after the module, Clang still finds each. (`make_xcframework` in `common.sh`.) |
| 7-Zip is linked into one object with only `zeig7z_*` exported | Its format handlers would otherwise be dropped by the linker, and its internals could clash with libarchive's. See `Native/zeig7z/README.md`. |
| libarchive bundles liblzma, zstd and lz4, but not zlib or bzip2 | The iOS SDK has zlib, bzip2, iconv and libxml2 with public headers (linked through the module map's `link` lines). It ships liblzma without headers, which isn't a public API, so XZ Utils is built. |
| No OpenSSL anywhere | libarchive uses CommonCrypto on Apple platforms (AES for zip and 7z), and 7-Zip and rars have their own crypto. The other crypto backends are switched off so CMake can't pick up a Homebrew OpenSSL for the Mac slice. |
| `LibArchiveBackend` switches the thread to a UTF-8 locale | libarchive converts names through the C locale, which is ASCII-only in an app. `uselocale` changes it for the calling thread only. |
| `strip = "none"` in `rars-ffi/Cargo.toml` | Stripped proc-macro dylibs don't load on macOS 27. The build script strips the copied static libraries instead. |

## Updating a library

1. Check out the new tag in its submodule:

   ```bash
   git -C Native/vendor/libarchive fetch --depth 1 origin tag v3.8.11
   ```

   ```bash
   git -C Native/vendor/libarchive checkout v3.8.11
   ```

2. Rebuild that library (`build-libarchive.sh` also rebuilds xz, zstd and lz4).
3. Run the tests: `CapabilityTests` checks versions and capability tables, and the round-trip
   tests check every format.
4. Update the version in Settings → Open Source (`SettingsFeature/AboutViews.swift`) and in the
   tables in this file and the README.

For rars, change the exact version in `Native/rars-ffi/Cargo.toml` and the string in
`rars_version()`; see `Native/rars-ffi/README.md`.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `no such module 'CSevenZip'` (or `CLibArchive`, `ZeigRarsFFI`) | The frameworks aren't built: run `Native/scripts/build-all.sh`. |
| Linker: "found architecture 'arm64', required architecture 'x86_64'" | Building for an Intel simulator. Use an Apple-silicon simulator, and regenerate the project (`xcodegen generate`) if `EXCLUDED_ARCHS` is missing. |
| `can't find crate for thiserror_impl` / "mis-aligned LINKEDIT string pool" | Someone turned stripping back on in `Cargo.toml`. |
| A test archive with non-ASCII names fails in libarchive with "Can't translate pathname" | A libarchive call outside `withUTF8Locale`. |
| 7-Zip extracts "ä" names as garbage, or can't find them | `us2fs`/`fs2us` used in `zeig7z.cpp`. |
| 7-Zip knows 0 formats | Its objects were put into the library one by one instead of linked with `clang -r` first. |
