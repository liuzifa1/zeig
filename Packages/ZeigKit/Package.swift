// swift-tools-version: 6.0
//
// ZeigKit — every module of the app except the thin app shell.
// See README.md in this folder for the dependency graph and module rules.
//
// The three binary targets are built from source by Native/scripts/build-*.sh into
// Frameworks/ (not checked in). Run Native/scripts/build-all.sh once after cloning.

import PackageDescription

let package = Package(
    name: "ZeigKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        // The app is iOS-only. macOS is here so `swift test` runs the backend tests on the Mac.
        .macOS(.v15),
    ],
    products: [
        .library(name: "ZeigCore", targets: ["ZeigCore"]),
        .library(name: "ZeigBackends", targets: ["ZeigBackends"]),
        .library(name: "ZeigStore", targets: ["ZeigStore"]),
        .library(name: "ZeigDesign", targets: ["ZeigDesign"]),
        .library(name: "BrowseFeature", targets: ["BrowseFeature"]),
        .library(name: "RecentFeature", targets: ["RecentFeature"]),
        .library(name: "SearchFeature", targets: ["SearchFeature"]),
        .library(name: "ArchiveFeature", targets: ["ArchiveFeature"]),
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
    ],
    targets: [
        // MARK: Native libraries (prebuilt by Native/scripts)

        .binaryTarget(name: "CSevenZip", path: "Frameworks/CSevenZip.xcframework"),
        .binaryTarget(name: "CLibArchive", path: "Frameworks/CLibArchive.xcframework"),
        .binaryTarget(name: "ZeigRarsFFI", path: "Frameworks/ZeigRarsFFI.xcframework"),
        // UniFFI's generated Swift for rars. Swift 5 mode: generated code, not ours to tidy.
        .target(
            name: "ZeigRars",
            dependencies: ["ZeigRarsFFI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // MARK: Foundation layer (no SwiftUI views)

        .target(name: "ZeigCore", exclude: ["README.md"]),
        .target(
            name: "ZeigBackends",
            dependencies: ["ZeigCore", "CSevenZip", "CLibArchive", "ZeigRars"],
            exclude: ["README.md"]
        ),
        .target(name: "ZeigStore", dependencies: ["ZeigCore"], exclude: ["README.md"]),

        // MARK: Design system

        .target(name: "ZeigDesign", dependencies: ["ZeigCore"], exclude: ["README.md"]),

        // MARK: Features

        .target(
            name: "ArchiveFeature",
            dependencies: ["ZeigCore", "ZeigBackends", "ZeigStore", "ZeigDesign"],
            exclude: ["README.md"]
        ),
        .target(
            name: "BrowseFeature",
            dependencies: ["ZeigCore", "ZeigStore", "ZeigDesign", "ArchiveFeature"],
            exclude: ["README.md"]
        ),
        .target(
            name: "RecentFeature",
            dependencies: ["ZeigCore", "ZeigStore", "ZeigDesign", "ArchiveFeature"],
            exclude: ["README.md"]
        ),
        .target(
            name: "SearchFeature",
            dependencies: ["ZeigCore", "ZeigStore", "ZeigDesign", "ArchiveFeature"],
            exclude: ["README.md"]
        ),
        .target(
            name: "SettingsFeature",
            dependencies: ["ZeigCore", "ZeigBackends", "ZeigStore", "ZeigDesign", "ArchiveFeature"],
            exclude: ["README.md"],
            // AppLogo: the About page's logo (a placeholder until the real artwork).
            resources: [.process("Resources/Media.xcassets")]
        ),

        // MARK: Tests

        .testTarget(name: "ZeigCoreTests", dependencies: ["ZeigCore"]),
        .testTarget(name: "ZeigStoreTests", dependencies: ["ZeigStore"]),
        .testTarget(
            name: "ZeigBackendsTests",
            dependencies: ["ZeigBackends"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
