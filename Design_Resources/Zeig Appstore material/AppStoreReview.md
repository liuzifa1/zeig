# Reply to App Review

Hello App Review Team,

Thank you for your message. Here is the requested information.

## 1. Physical-device recording and permissions

Zeig is a completely offline, on-device archive utility. It has no accounts, purchases, subscriptions, paid features, ads, analytics, public/user-generated content service, reporting, or blocking flows, and it never makes network requests.

Zeig does not request Location, Contacts, Camera, Microphone, Photos, Local Network, or App Tracking Transparency permissions.

Capabilities declared in `Info.plist`:
- **Files app integration (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`):** exposes Zeig's sandboxed `Documents` folder in the Files app as `On My iPhone › Zeig` (`On My iPad › Zeig`). Files opened from other apps (`CFBundleDocumentTypes` / "Open in Zeig") are copied or moved into Zeig's own folder before processing.
- **Export compliance (`ITSAppUsesNonExemptEncryption: false`):** password-protected archive encryption (ZIP AES-256 / ZipCrypto, 7z AES-256, optional RAR) is strictly local on-device file archiving with no network transmission.
- **Background Modes (`UIBackgroundModes: [audio]` — Guideline 2.5.4):** strictly required by iOS for `AVPictureInPictureController` so the opt-in **Developer Mode > Console > Picture in picture** floating diagnostic log window (`ConsolePictureInPicture`, enabled only after tapping **Settings > App** version seven times and turning on **Picture in picture**) can appear above other apps. Zeig plays no audible audio, records no audio, and does not run in the background otherwise.

## 2. Tested devices

The submitted iPhone/iPad build was tested on:
- [Fill in physical iPhone model & iOS version/build before submitting, e.g. iPhone 15 Pro — iOS 26.x]
- [Fill in physical iPad model & iPadOS version/build before submitting, e.g. iPad Pro 11-inch — iPadOS 26.x]

Simulator verification during asset preparation was also performed on:
- iPhone 17 Pro Max — iOS 26.2
- iPad Pro 13-inch (M5) — iPadOS 26.2

## 3. Purpose and functionality

Zeig is a native archive manager for iPhone and iPad (iOS / iPadOS 18+, with Liquid Glass on 26+) that opens and creates archives locally on the device.

Key features:
- **Broad format support:** opens and creates ZIP, 7z, TAR, compressed tar formats (`tar.gz`, `tar.bz2`, `tar.xz`, `tar.zst`, `tar.lz4`), GZIP, BZIP2, XZ, Zstandard, LZ4, Lzip, LZMA, Unix compress (`.Z`), ISO, CPIO, XAR, and WIM. Opens RAR, CAB, DMG, LZH, AR, DEB, ARJ, CHM, RPM, MSI, SquashFS, VHD/VHDX, VMDK, and other formats detected by 7-Zip from content.
- **Files-style browsing:** navigate folders in place with back/forward history, expand subfolders inline, view Quick Look thumbnails for images/PDFs/text, use two-finger drag or `+ > Select` for multi-selection, and move files via the system move sheet.
- **Inspect & extract selectively:** browse inside an archive folder by folder before extracting, preview individual files in Quick Look, extract a single file/folder via long-press, or tap **Extract All** to extract into a sibling folder.
- **Passwords & archive tools:** prompt for passwords on encrypted archives (passwords are never stored), run **Test Archive**, share archives, and inspect archive statistics (**Info**: compression ratio, space savings, file/folder counts, method, solid mode, and engine used).
- **Create archives:** configure archive name, format, compression level, optional password (ZIP, 7z, and opt-in RAR), and per-format **Advanced settings** with built-in **Format Guide** explanations.
- **Recent, Search, and "Open in Zeig":** day-grouped recent activity, instant filename/archive search, and importing archives shared from Files or other apps.
- **Opt-in experimental RAR creation:** disabled by default behind **Settings > Experimental > Test RAR backend** with an explicit warning; every created RAR is automatically verified by 7-Zip.

## 4. Review instructions

No credentials, account, subscription, activation code, or external sample file is required.

1. Open Zeig on the **Browse** tab, tap `+ > New Folder` or `+ > Import from Files…` to add any sample file(s), or add files through the Files app under `On My iPhone › Zeig`.
2. Long-press an item and choose **Compress** (or tap `+ > Select`, select one or more items, and tap **Compress** in the bottom toolbar). Choose a format (such as ZIP or 7z), compression level, and optional password, then tap **Create**.
3. Tap the created archive to browse its internal folders and sizes; tap any file inside to preview it in Quick Look; long-press a file or folder inside the archive to extract just that item, or tap **Extract All** to extract everything into a new folder next to the archive.
4. Inside an archive, tap the `⋯` menu to run **Test Archive**, **Share**, or **Info** (original/compressed size, savings, compression method, and backend engine).
5. Switch to **Recent** to see day-grouped history and **Search** to filter across **All Files** or **Archives**.
6. Optional "Open in Zeig" test: share or open any `.zip`, `.7z`, `.rar`, or `.tar.gz` file from the Files app into Zeig.
7. Optional Settings review: tap the gear button to inspect **Format Guide**, **Backends**, **Privacy Policy**, **Open Source Acknowledgements**, and the opt-in **Experimental > Test RAR backend** switch (which displays a confirmation warning and verifies generated RARs with 7-Zip).
8. Optional Developer Mode / PiP review (for `UIBackgroundModes: audio`): tap **Settings > App** version seven times to reveal **Developer**, open **Console**, and toggle **Picture in picture** on a physical device (Picture in Picture is hidden on the iOS Simulator where iOS reports PiP as unsupported).

## 5. Services and technology

Zeig requires no remote data, server, authentication, payment, analytics, advertising, cloud-file, or AI service. All archive inspection, extraction, and creation happen locally on the device.

The app embeds open-source native archive engines built from source:
- **7-Zip 26.05** (`Native/vendor/7zip` and `Native/zeig7z`, GNU LGPL 2.1+ and BSD 3-Clause parts; RAR decompression carries the unRAR restriction and is never used for RAR creation). Full source and build scripts are included in the repository.
- **libarchive 3.8.10** (BSD 2-Clause), linked with **XZ Utils 5.8.4** (0BSD), **Zstandard 1.5.7** (BSD 3-Clause), and **LZ4 1.10.0** (BSD 2-Clause).
- **rars 0.12.3** (Apache 2.0) via **UniFFI 0.32.2** (MPL 2.0) — independent Rust RAR implementation used only when the experimental toggle is enabled by the user.
- Full component versions, licenses, and repository links are displayed in-app under **Settings > Open Source Acknowledgements**.
- Apple APIs: SwiftUI, QuickLook, QuickLookThumbnailing, UniformTypeIdentifiers, system `fileImporter` / `fileMover`, and AVKit (`AVPictureInPictureController` for the opt-in developer console window).

## 6. Regions, regulation, and third-party material

Zeig has no regional differences in features, pricing, or availability.

Zeig is not a regulated service and provides no protected third-party media, financial, medical, gambling, cryptocurrency, or other regulated content. Open-source libraries are used in compliance with their respective licenses, listed in-app. Zeig is not affiliated with or endorsed by 7-Zip, libarchive, or RARLAB. RAR is a trademark of win.rar GmbH.

This information is also provided in the App Review Information Notes field.

Thank you.
