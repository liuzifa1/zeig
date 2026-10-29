# Zeig

A native archive app for iPhone and iPad: open and create ZIP, 7z, tar and many more formats,
on the device, in Swift and SwiftUI.

- **Platforms:** iOS / iPadOS 18+. Liquid Glass on 26+, with material fallbacks below.
- **Engines:** [7-Zip](https://www.7-zip.org) (main), [libarchive](https://www.libarchive.org)
  (the formats 7-Zip can't create), and, experimental and off by default,
  [rars](https://github.com/bitplane/rars) for creating RAR archives.
- **No third-party Swift packages.** The engines are built from source (`Native/`).
- **License:** MIT for Zeig's code; see [Licenses](#licenses) for the engines.

## Features

| Area | What it does |
|---|---|
| **Browse** | The app's own folder (also in the Files app as On My iPhone › Zeig). A Photos-style header: large title, item count and size under it, and glass **+** and **Settings** buttons at the top right. Works like Files: tap a folder to go into it, with **back/forward** buttons; the chevron beside a folder expands it in place, with its contents sliding in under it; Quick Look thumbnails for images, PDFs and text. Archives push; other files open in Quick Look. |
| **Long-press menu** | Like Files: **Copy · Move · Share** across the top, then Quick Look, Open In…, Get Info, Rename, Extract (archives) or Compress, Duplicate, New Folder with Item, Delete. Works on a selection too. Swipe left to delete. Deleting never asks first, as in Files, and it's permanent: there's no Recently Deleted. |
| **Selecting** | Two-finger drag down the list, or + → Select. The header becomes **Select All · N Items · ✓**, and a toolbar takes the tab bar's place: **Extract · Compress · Move · Delete**, then ⋯ (Share, Copy N Items, New Folder with Items). **Move** opens the system's move sheet, so files can also go to iCloud Drive or another app's folder. |
| **+ menu** | Import from Files… (copies files in), Paste (files copied here or in Files), New Folder, Select. |
| **Archives** | Tap to see what's inside, folder by folder, with sizes, dates and a lock on encrypted files. Tap a file to preview it, long-press a file or folder to extract just that, or **Extract All** into a new folder next to the archive ("photos.zip" → "photos", "photos 2" if taken). ⋯: Test Archive, Share, Info: how much it saves (compressed to N%, original and archive size), file and folder counts, encrypted files, dates, format, method, solid, parts, comment, and which engine opened it. |
| **Passwords** | Asked for when needed, with "wrong password, try again". Never stored. |
| **Create** | Name, format (common ones first, the rest under *More formats*), compression level, password (ZIP, 7z, RAR), and per-format **Advanced settings**, each with a one-line explanation and an ⓘ for the full one. Remembers your last advanced settings per format. |
| **Recent** | Files you opened, created, extracted or imported, by day. Same header as Browse; its + menu imports files or clears the list. |
| **Search** | File names anywhere in the app's folder, with an **All Files \| Archives** switch showing counts. The tab bar's separate search button. |
| **Settings** | Default format and level; **Experimental** (test RAR backend); Format Guide; the app's version; Backends (which engine does what, and each engine's version); About, Privacy Policy, Open Source Acknowledgements. |
| **Developer mode** | Tap the App version in Settings seven times. **Console**: the log of what the engines do (routing decisions, engine details, timings, errors), as a sheet with search, a level filter, share, export and clear; a console button appears next to Settings in Browse and Recent. **Picture in picture** shows the latest lines in the system's floating video window, over other apps too; its back button opens the full console. **Export Log…** saves the log as a text file. **Capture native output** adds what the C, C++ and Rust code prints. **Font Lab**: a face (system, rounded, New York, mono, or any installed family) and a size for titles, file names, subtitles, indicators and guide text, with a live preview. |
| **Open in Zeig** | Archives shared from other apps are moved or copied into the app's folder and opened. |

## Formats

The routing rule (`BackendRouter`): a format 7-Zip can create belongs to 7-Zip, for opening and
creating. Formats 7-Zip doesn't have, or can only open while libarchive can also create them,
belong to libarchive. Formats both can only open go to 7-Zip. If the first choice can't open a
file, the other engine tries.

| Format | Creates | Opens |
|---|---|---|
| ZIP, 7z, TAR, GZIP, BZIP2, XZ, WIM | 7-Zip | 7-Zip |
| tar.gz, tar.bz2, tar.xz, tar.zst, tar.lz4 | libarchive | libarchive |
| Zstandard, LZ4, Lzip, LZMA, .Z | libarchive | libarchive |
| ISO, CPIO, XAR | libarchive | libarchive |
| **RAR** | rars, *experimental, opt-in* | 7-Zip (or rars, if you choose) |
| CAB, LZH, AR, DEB | — | 7-Zip |
| DMG, ARJ, CHM, RPM, MSI, SquashFS, VHD/VHDX, VMDK | — | 7-Zip |
| Anything else 7-Zip recognizes (APFS, HFS, NTFS/FAT/ext images, UDF, NSIS, QCOW, VDI, …) | — | 7-Zip, by content |

Settings → Backends shows this table live.

**Advanced settings** per format: ZIP: method, encryption (AES-256 or ZipCrypto). 7z: method,
dictionary size, solid, encrypt file names. Compressed tars: tar flavor (pax, GNU, ustar). ISO:
volume name, Joliet, Rock Ridge. RAR: version (7, 5, 2.9), solid, encrypt file names, recovery
record, split into parts.

### RAR creation is experimental

RAR is proprietary, and RARLAB's own code can't be built into apps. Zeig creates RAR archives
with rars, an independent open-source implementation that is still young. So:

- It's **off** until you turn on Settings → Experimental → *Test RAR backend*, after a warning.
- RAR shows as *RAR (experimental)* in the format list, with a warning when chosen.
- **Every RAR rars creates is opened and tested by 7-Zip**, which also checks the file names
  come out the same. If the check fails you're told, and the archive is kept so you can decide.
- Opening RAR stays with 7-Zip unless you also turn on *Use it for opening RAR too*.

Known rars limitation: RAR 2.9 archives with non-English file names show garbled names in other
apps (the check catches it). RAR 5 and 7 are fine.

RAR is a trademark of win.rar GmbH. Zeig isn't affiliated with it.

## Getting started

```bash
brew install xcodegen cmake
```

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin
```

```bash
git submodule update --init
```

```bash
Native/scripts/build-all.sh
```

```bash
xcodegen generate
```

```bash
open Zeig.xcodeproj
```

The first native build takes about 15 minutes; later ones reuse `~/Library/Caches/Zeig/native`.
The `.xcodeproj` is generated from `project.yml` and git-ignored: edit `project.yml`, then
regenerate. Simulator builds need an Apple-silicon Mac.

> **iCloud Drive.** This folder may be iCloud-synced. Keep build output out of it: Xcode's
> default DerivedData is fine, and give `swift build` / `swift test` a `--scratch-path`
> outside it (as below). The native scripts already build in `~/Library/Caches`.

## Tests

```bash
swift test --package-path Packages/ZeigKit --scratch-path "$TMPDIR/zeigkit-build"
```

```bash
CARGO_TARGET_DIR=~/Library/Caches/Zeig/native/cargo cargo test --manifest-path Native/rars-ffi/Cargo.toml --lib
```

The Swift tests run on the Mac against the real libraries (the frameworks include a macOS
slice for this). They create, open, extract and compare every format Zeig can create, and also
cover passwords, archives with `../` paths (nothing may land outside the destination),
cancelling, cross-reading between engines, and the routing rule format by format.

### RAR test files

To test the RAR readers against archives made by RARLAB's own `rar`:

1. Put a few small files (a few MB at most) in `Native/fixtures/rar-input/`, ideally a
   subfolder, a non-English file name and an empty folder.
2. Optional: put ready-made `.rar` files in `Native/fixtures/rar-extra/`, such as RAR4 archives
   from an old WinRAR (rar 7 can't create those) or multi-volume sets.
3. Run:

   ```bash
   Native/scripts/make-rar-fixtures.sh
   ```

It makes RAR5 archives (normal, store, best, solid, password, encrypted names, recovery record,
split volumes), copies your extras, and writes `manifest.json` with every file's checksum. For
extras, `unrar` decides what the right contents are. `RarFixtureTests` then has both 7-Zip and
rars extract each one and compare. Commit
`Packages/ZeigKit/Tests/ZeigBackendsTests/Fixtures/RAR/archives/`.

## Project layout

```
App/                      entry point and tabs (thin)
Packages/ZeigKit/         every Swift module; see its README for the dependency graph
Native/                   7-Zip, libarchive and rars, the bridges, and the build scripts
docs/native-builds.md     how the native libraries are built, and the odd parts explained
Native/zeig7z/README.md   the C layer over 7-Zip
Native/rars-ffi/README.md the Rust/UniFFI layer over rars, with a walkthrough
AGENTS.md                 conventions (for AI agents, and a good summary for people too)
```

## Licenses

| Component | License | Where |
|---|---|---|
| Zeig | MIT | `LICENSE` |
| 7-Zip 26.05 | GNU LGPL 2.1+, parts BSD 3-Clause; its RAR decoder carries the unRAR restriction (may not be used to re-create the RAR compressor) | `Native/vendor/7zip` |
| Zeig's 7-Zip bridge | GNU LGPL 2.1+ (derived from 7-Zip's Client7z sample) | `Native/zeig7z` |
| libarchive 3.8.10 | BSD 2-Clause | `Native/vendor/libarchive` |
| XZ Utils 5.8.4 | 0BSD | `Native/vendor/xz` |
| Zstandard 1.5.7 | BSD 3-Clause | `Native/vendor/zstd` |
| LZ4 1.10.0 | BSD 2-Clause | `Native/vendor/lz4` |
| rars 0.12.3 | Apache 2.0 | fetched by Cargo |
| UniFFI 0.32 | MPL 2.0 | fetched by Cargo |
| PageHeader / glass helpers | MIT (from HNReader, same author) | `ZeigDesign` |

7-Zip is used under the LGPL: its source, the bridge, and the script that builds them are all
in this repository, so the library can be modified and rebuilt. RAR creation uses rars, not
7-Zip's RAR code.
