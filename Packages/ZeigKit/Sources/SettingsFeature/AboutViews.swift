import SwiftUI
import ZeigBackends
import ZeigCore
import ZeigDesign
import ZeigStore

/// Name, version and links shown in Settings.
enum AppInfo {
    static let displayName = "Zeig"

    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    /// The public repository. `nil` until it's published; the About page hides the link.
    static let sourceURL: URL? = nil

    static let copyright = "© 2026 Zifa Liu. Released under the MIT License."
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
/// is, and the copyright, top-aligned. The logo is `AppLogo` in Resources/Media.xcassets
/// (a placeholder until the real artwork).
struct AboutAppView: View {
    var body: some View {
        ScrollView {
            Section {
                VStack(alignment: .leading) {
                    VStack(alignment: .leading) {
                        Image("AppLogo", bundle: .module)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                            .accessibilityHidden(true)
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
            detail: "Igor Pavlov. Archive handlers and codecs; Zeig's C bridge to it (Native/zeig7z) is adapted from 7-Zip's Client7z sample and shares its license. The RAR decompression code carries the unRAR restriction: it may not be used to re-create the RAR compression algorithm. Zeig doesn't: RAR creation is done by rars, an independent implementation.",
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
                Text("7-Zip is used under the LGPL: its source, and the bridge Zeig adds to it, are in Zeig's repository (Native/vendor/7zip, Native/zeig7z), with the script that builds the library (Native/scripts/build-7zip.sh), so it can be modified and rebuilt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Open Source")
        .inlineNavigationTitle()
    }
}
