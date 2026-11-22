# Zeig — App Store Connect Metadata

## Listing Fields

- **App Name:** `Zeig!`
- **Subtitle (27 / 30 chars):** `ZIP, 7z, RAR & Tar Archives`
- **Primary Category:** `Utilities`
- **Secondary Category:** `Productivity`
- **Copyright:** `© 2026 Zifa Liu`
- **Price:** Free
- **Age Rating:** 4+
- **Support URL:** `https://liuzifa1.github.io/zeig/` (`docs/index.html`, GitHub Pages from `main` `/docs`)
- **Privacy Policy URL:** `https://liuzifa1.github.io/zeig/privacy-policy.html`
- **Keywords (83 / 100 chars):**
  ```
  zip,7z,rar,tar,unzip,unrar,archive,extract,compress,file,manager,7zip,zstd,iso,gzip
  ```

### Promotional Text (158 / 170 chars)

```
Open and create ZIP, 7z, tar, GZIP, Zstandard, ISO, and more directly on iPhone and iPad. Powered by 7-Zip and libarchive, 100% offline with zero tracking.
```

### Description

```
Zeig is a fast, native archive manager for iPhone and iPad. Browse files like the Files app, peek inside archives before extracting, and create compressed archives in dozens of formats—all completely offline on your device.

OPEN & CREATE ARCHIVES ON DEVICE
• Create & open: ZIP, 7z, TAR, TAR.GZ, TAR.BZ2, TAR.XZ, TAR.ZST, TAR.LZ4, GZIP, BZIP2, XZ, Zstandard, LZ4, Lzip, LZMA, Unix compress (.Z), ISO, CPIO, XAR, and WIM.
• Open & extract: RAR, CAB, DMG, LZH, AR, DEB, ARJ, CHM, RPM, MSI, SquashFS, VHD/VHDX, VMDK, and many more formats detected automatically by content.
• Opt-in experimental RAR creation via rars, automatically checked with 7-Zip.

INSPECT BEFORE YOU EXTRACT
• Browse the folder tree inside any archive with file sizes, dates, and lock indicators on encrypted items.
• Tap any file inside an archive to preview it immediately with Quick Look.
• Extract a single file or folder, or tap Extract All to unpack cleanly into a folder next to the archive.
• Run Test Archive to verify integrity or open Info to inspect compression savings, method, and engine details.

BUILT FOR iOS & iPadOS
• Files-style Browse tab with inline folder expansion, Quick Look thumbnails, back/forward navigation, drag selection, and system Move sheet support.
• Create archives with custom names, compression levels, optional passwords (ZIP AES-256 / ZipCrypto, 7z), and per-format Advanced settings with built-in Format Guide explanations.
• Recent tab grouped by day, instant Search across all files or archives only, and Open in Zeig from Files and other apps.
• Designed in SwiftUI with Liquid Glass on iOS 26 and iPadOS 26.

PRIVATE BY DESIGN
• Works 100% offline—your files never leave your device.
• No accounts, no ads, no analytics, and no tracking.
• Passwords are used only for the current operation and are never stored.

Not affiliated with 7-Zip, libarchive, or RARLAB. RAR is a trademark of win.rar GmbH.
```

## App Review Notes

The notes field takes at most 4,000 characters: paste `AppReviewNotes.txt`, a condensed
`AppStoreReview.md`.

## App Privacy (Nutrition Label)

- **Data Not Collected:** Zeig does not collect, sell, share, or track any user data. No third-party SDKs, no analytics, and no network connections.

---

## Screenshot Asset Inventory

All images are opaque (App Store Connect rejects an alpha channel). Re-render with
`swift render_screenshots.swift` from this folder.

### iPhone 6.3" Display (`1206 × 2622`, Display P3) — required slot

`browse-6.3.png`, `archive-6.3.png`, `create-6.3.png`, `recent-6.3.png`: the same scenes as
below, scaled from the 6.5" layout.

### iPhone 6.5" Display (`1284 × 2778`, Display P3) — optional slot

| File | Scene | Headline |
|---|---|---|
| `browse.png` | Browse tab with expanded folder & thumbnails | Open and manage every archive format |
| `archive.png` | Opened `.7z` archive tree, encrypted badge & Extract All | Inspect and extract exactly what you need |
| `create.png` | New Archive sheet (format, compression level, password) | Create ZIP, 7z, tar and more on device |
| `recent.png` | Recent tab grouped by Today & Yesterday | Pick up recent archives where you left off |

### iPad 13" Display Portrait (`2048 × 2732`, Display P3)

| File | Scene | Headline |
|---|---|---|
| `browseiPad.png` | Browse tab with expanded folder & thumbnails | Open and manage every archive format |
| `archiveiPad.png` | Opened `.7z` archive tree, encrypted badge & Extract All | Inspect and extract exactly what you need |
| `createiPad.png` | New Archive sheet (format, compression level, password) | Create ZIP, 7z, tar and more on device |
| `recentiPad.png` | Recent tab grouped by Today & Yesterday | Pick up recent archives where you left off |
