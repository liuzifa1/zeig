# ZeigKit

Every module of Zeig except the thin app shell, one SwiftPM target each.

```
            App/
              │
   ┌──────────┼──────────────┬───────────────┐
BrowseFeature RecentFeature SearchFeature SettingsFeature
   └──────────┴──────┬───────┴───────────────┘
               ArchiveFeature         (screens every tab pushes)
          ┌──────────┼──────────┐
     ZeigBackends  ZeigStore  ZeigDesign
     │    │    │       │          │
     │    │  ZeigRars  └────┬─────┘
     │    │    │         ZeigCore     (formats, routing, options, errors)
 CSevenZip CLibArchive ZeigRarsFFI   (binary targets built by Native/scripts)
```

Dependencies only point downwards; `Package.swift` is the source of truth. Each module's
folder has a README with its main types.

Tests (`Tests/`): `ZeigCoreTests`, `ZeigStoreTests`, `ZeigBackendsTests` (runs the real
libraries on the Mac). Run them with:

```bash
swift test --package-path Packages/ZeigKit --scratch-path "$TMPDIR/zeigkit-build"
```

`Frameworks/` (git-ignored) holds the built `.xcframework`s; see `docs/native-builds.md`.
