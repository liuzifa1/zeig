import SwiftUI
import ZeigBackends
import ZeigCore
import ZeigDesign
import ZeigStore
#if canImport(UIKit)
import UIKit
#endif

/// Name, version and links shown in Settings.
enum AppInfo {
    static let displayName = "Zeig!"

    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    /// The public repository. `nil` until it's published; the About page hides the link.
    static let sourceURL: URL? = nil

    static let copyright = "© 2026 Arc Liu"
}

/// Settings → Backends: which engine handles which format, and their versions.
struct BackendsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let router = BackendRouter(settings: settings.routing)
        List {
            Section {
                backend(.sevenZip, version: SevenZipBackend().version, role: "Main backend. Opens almost every format, and creates ZIP, 7z, TAR, GZIP, BZIP2, XZ and WIM.")
                backend(.libArchive, version: LibArchiveBackend().version, role: "Creates and opens the formats 7-Zip can't create: tar.gz and other compressed tars, Zstandard, LZ4, ISO, CPIO, XAR and more. Also tries files 7-Zip can't open.")
                backend(.rars, version: RarsBackend().version, role: settings.rarsEnabled
                        ? "Turned on. Creates RAR archives\(settings.rarsOpensRar ? " and opens them" : ""). Experimental."
                        : "Off. Turn on in Settings → Experimental to create RAR archives.")
            }
            Section {
                ForEach(ArchiveFormat.allCases) { format in
                    HStack {
                        Text(format.displayName)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Opens: \(router.opener(for: format).displayName)")
                            Text("Creates: \(router.creator(for: format)?.displayName ?? "–")")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("By format")
            } footer: {
                Text("7-Zip handles a format when it can both create and open it. libarchive takes the formats 7-Zip doesn't have, or can only open while libarchive can create them too. If a format can only be opened, 7-Zip opens it. Formats not listed are detected by 7-Zip from their contents.")
            }
            Section("libarchive build") {
                Text(LibArchiveBackend().versionDetails)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Backends")
        .inlineNavigationTitle()
    }

    private func backend(_ id: BackendID, version: String, role: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(id.displayName).font(.headline)
                if id == .rars { ExperimentalBadge() }
                Spacer()
                Text(version).foregroundStyle(.secondary)
            }
            Text(role).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// About page, laid out like Filz!'s: the logo, the name, what the app is, where the source
/// is, and the copyright, top-aligned. The logo is the Splash artwork (`Splash` in the app's
/// asset catalog). Easter egg: three taps on it switch the app icon to the Splash version and
/// back (`AppIconChanger`).
struct AboutAppView: View {
    @State private var logoTaps = TapCounter(needed: 3)

    var body: some View {
            Section {
                VStack(alignment: .leading) {
                    VStack(alignment: .leading) {
                        Image("Splash")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if logoTaps.tap() { AppIconChanger.toggleSplash() }
                            }
                            .accessibilityLabel("\(AppInfo.displayName) logo")
                        Text(AppInfo.displayName)
                            .font(.headline)
                    }
                    Spacer()
                    Text("\(AppInfo.displayName) is an open source project that aims to provide a native archive experience on iOS, with 7-Zip and libarchive doing the work.")
                        .foregroundStyle(.secondary)
                    if let url = AppInfo.sourceURL {
                        HStack(spacing: 4) {
                            Text("You can find its source code at")
                                .foregroundStyle(.secondary)
                            Link("here...", destination: url)
                        }
                    }
                    Text("Not affiliated with 7-Zip, libarchive or RARLAB. RAR is a trademark of win.rar GmbH.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(AppInfo.copyright)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        .navigationTitle(AppInfo.displayName)
    }
}

/// What the app stores and talks to. Kept in code so it ships with the app and works offline.
struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section {
                Text("\(AppInfo.displayName) doesn't collect, sell, share or track any data.")
                    .font(.headline)
                Text("There are no accounts, analytics, ads or third-party SDKs, and the app never connects to the internet.")
                    .foregroundStyle(.secondary)
            }
            Section("Your files") {
                Text("Archives are opened and created on your device. Files never leave it unless you share them yourself.")
                Text("Files you import are copied into \(AppInfo.displayName)'s own folder (On My iPhone › \(AppInfo.displayName) in the Files app). Deleting the app deletes that folder.")
            }
            Section("Stored on this device") {
                Text("Your settings and the Recent list. Clear Recent from the + menu on the Recent tab.")
                Text("Passwords you type are used for that one operation and never stored.")
            }
            Section("Contact") {
                Text("Questions? Contact the developer through the page where you got \(AppInfo.displayName).")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Privacy Policy")
        .inlineNavigationTitle()
    }
}

/// The open source code inside the app, with licenses.
struct OpenSourceView: View {
    private struct Component: Identifiable {
        let name: String
        let version: String?
        let detail: String
        let license: String
        let url: URL
        var id: String { name }
    }

    private let components = [
        Component(
            name: "7-Zip", version: SevenZipBackend().version,
            detail: "Igor Pavlov. Archive handlers and codecs; Zeig!'s C bridge to it (Native/zeig7z) is adapted from 7-Zip's Client7z sample and shares its license. The RAR decompression code carries the unRAR restriction: it may not be used to re-create the RAR compression algorithm. Zeig! doesn't: RAR creation is done by rars, an independent implementation.",
            license: "GNU LGPL 2.1 or later, BSD 3-Clause (parts), unRAR license restriction",
            url: URL(string: "https://www.7-zip.org")!
        ),
        Component(
            name: "libarchive", version: LibArchiveBackend().version,
            detail: "Tim Kientzle and contributors. Multi-format archive library.",
            license: "BSD 2-Clause",
            url: URL(string: "https://www.libarchive.org")!
        ),
        Component(
            name: "XZ Utils (liblzma)", version: "5.8.4",
            detail: "Lasse Collin and contributors. XZ and LZMA compression for libarchive.",
            license: "BSD Zero Clause (0BSD)",
            url: URL(string: "https://tukaani.org/xz/")!
        ),
        Component(
            name: "Zstandard", version: "1.5.7",
            detail: "Meta Platforms, Inc. and contributors.",
            license: "BSD 3-Clause",
            url: URL(string: "https://github.com/facebook/zstd")!
        ),
        Component(
            name: "LZ4", version: "1.10.0",
            detail: "Yann Collet and contributors.",
            license: "BSD 2-Clause",
            url: URL(string: "https://github.com/lz4/lz4")!
        ),
        Component(
            name: "rars", version: RarsBackend().version,
            detail: "bitplane and contributors. Independent RAR implementation in Rust, used for the experimental RAR backend. Its Rust dependencies (aes, hmac, sha1, sha2, crc32fast, aho-corasick, rayon, getrandom, zeroize) are MIT / Apache 2.0.",
            license: "Apache 2.0",
            url: URL(string: "https://github.com/bitplane/rars")!
        ),
        Component(
            name: "UniFFI", version: "0.32.2",
            detail: "Mozilla. Generates the Swift bindings for rars.",
            license: "Mozilla Public License 2.0",
            url: URL(string: "https://github.com/mozilla/uniffi-rs")!
        ),
        Component(
            name: "Rust standard library", version: nil,
            detail: "The Rust Project Developers. Linked into the rars backend.",
            license: "MIT / Apache 2.0",
            url: URL(string: "https://www.rust-lang.org")!
        ),
    ]

    var body: some View {
        List {
            Section {
                Text("\(AppInfo.displayName) is open source under the MIT License and built on the projects below. zlib, bzip2, iconv and libxml2 are provided by iOS itself.")
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(components) { component in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(component.name).font(.headline)
                            Spacer()
                            if let version = component.version { Text(version).foregroundStyle(.secondary) }
                        }
                        Text(component.detail).font(.subheadline).foregroundStyle(.secondary)
                        Text(component.license).font(.caption)
                        Link(component.url.host() ?? component.url.absoluteString, destination: component.url)
                            .font(.caption)
                    }
                    .padding(.vertical, 2)
                }
            }
            Section {
                Text("7-Zip is used under the LGPL: its source, and the bridge Zeig! adds to it, are in Zeig!'s repository (Native/vendor/7zip, Native/zeig7z), with the script that builds the library (Native/scripts/build-7zip.sh), so it can be modified and rebuilt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Open Source")
        .inlineNavigationTitle()
    }
}

#Preview {
    AboutAppView()
}

/// Counts taps that come close together: `tap()` is true on the `needed`th one. More
/// forgiving than a triple-tap gesture, whose taps must be very quick.
struct TapCounter {
    let needed: Int
    /// The longest gap between two taps that still counts.
    var window: TimeInterval = 1.5
    private var count = 0
    private var last = Date.distantPast

    init(needed: Int) {
        self.needed = needed
    }

    mutating func tap(at now: Date = .now) -> Bool {
        count = now.timeIntervalSince(last) <= window ? count + 1 : 1
        last = now
        guard count >= needed else { return false }
        count = 0
        return true
    }
}

/// Switches the home screen icon between the main one (App/App.icon) and the Splash version
/// (App/AppSplash.icon, listed in `project.yml` as an alternate icon). iOS confirms the change
/// with its own alert.
@MainActor
enum AppIconChanger {
    /// The alternate icon's name in the app's asset catalog.
    static let splash = "AppSplash"

    static func toggleSplash() {
        #if canImport(UIKit)
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else {
            ZeigLog.info("icon", "alternate icons aren't supported here")
            return
        }
        let next = app.alternateIconName == splash ? nil : splash
        Task {
            do {
                try await app.setAlternateIconName(next)
                ZeigLog.info("icon", "icon is now \(next ?? "the default")")
            } catch {
                // The Simulator often changes the icon and then fails to show iOS's alert,
                // which reports an error too: say which icon is set now.
                ZeigLog.error("icon", "couldn't change the icon: \(error.localizedDescription); it's \(app.alternateIconName ?? "the default")")
            }
        }
        #endif
    }
}
