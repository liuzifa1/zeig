import Foundation

/// Every archive format Zeig knows by name.
///
/// Which backend handles a format, and whether it can be created or only opened, is decided
/// by `BackendRouter` from `BackendCapabilities`, not here. Formats not listed can still
/// be opened: 7-Zip detects them from the file's contents (`ArchiveFormat?` is `nil`).
public enum ArchiveFormat: String, CaseIterable, Sendable, Codable, Identifiable {
    // Archives (many files)
    case zip
    case sevenZip = "7z"
    case rar
    case tar
    case tarGzip = "tar.gz"
    case tarBzip2 = "tar.bz2"
    case tarXz = "tar.xz"
    case tarZstd = "tar.zst"
    case tarLz4 = "tar.lz4"
    case iso
    case cpio
    case xar
    case ar
    case wim

    // Single-file compressors
    case gzip = "gz"
    case bzip2 = "bz2"
    case xz
    case zstd = "zst"
    case lz4
    case lzip = "lz"
    case lzma
    case compress = "Z"

    // Open-only formats worth naming (7-Zip reads many more)
    case cab
    case dmg
    case lzh
    case arj
    case chm
    case rpm
    case deb
    case msi
    case squashfs
    case vhd
    case vmdk

    public var id: String { rawValue }

    /// Name shown in the UI.
    public var displayName: String {
        switch self {
        case .zip: "ZIP"
        case .sevenZip: "7z"
        case .rar: "RAR"
        case .tar: "TAR"
        case .tarGzip: "TAR.GZ"
        case .tarBzip2: "TAR.BZ2"
        case .tarXz: "TAR.XZ"
        case .tarZstd: "TAR.ZST"
        case .tarLz4: "TAR.LZ4"
        case .iso: "ISO"
        case .cpio: "CPIO"
        case .xar: "XAR"
        case .ar: "AR"
        case .wim: "WIM"
        case .gzip: "GZIP"
        case .bzip2: "BZIP2"
        case .xz: "XZ"
        case .zstd: "Zstandard"
        case .lz4: "LZ4"
        case .lzip: "Lzip"
        case .lzma: "LZMA"
        case .compress: "Unix compress (.Z)"
        case .cab: "Cabinet"
        case .dmg: "Disk image (DMG)"
        case .lzh: "LZH"
        case .arj: "ARJ"
        case .chm: "CHM"
        case .rpm: "RPM"
        case .deb: "Debian package"
        case .msi: "Windows Installer"
        case .squashfs: "SquashFS"
        case .vhd: "VHD"
        case .vmdk: "VMDK"
        }
    }

    /// Extension Zeig writes, without the dot.
    public var fileExtension: String { extensions[0] }

    /// Extensions recognized when opening, longest first so "tar.gz" wins over "gz".
    public var extensions: [String] {
        switch self {
        case .zip: ["zip", "zipx"]
        case .sevenZip: ["7z"]
        case .rar: ["rar"]
        case .tar: ["tar"]
        case .tarGzip: ["tar.gz", "tgz"]
        case .tarBzip2: ["tar.bz2", "tbz2", "tbz"]
        case .tarXz: ["tar.xz", "txz"]
        case .tarZstd: ["tar.zst", "tzst"]
        case .tarLz4: ["tar.lz4"]
        case .iso: ["iso"]
        case .cpio: ["cpio"]
        case .xar: ["xar", "pkg"]
        case .ar: ["ar", "a"]
        case .wim: ["wim", "esd"]
        case .gzip: ["gz", "gzip"]
        case .bzip2: ["bz2", "bzip2"]
        case .xz: ["xz"]
        case .zstd: ["zst"]
        case .lz4: ["lz4"]
        case .lzip: ["lz"]
        case .lzma: ["lzma"]
        case .compress: ["Z"]
        case .cab: ["cab"]
        case .dmg: ["dmg"]
        case .lzh: ["lzh", "lha"]
        case .arj: ["arj"]
        case .chm: ["chm"]
        case .rpm: ["rpm"]
        case .deb: ["deb"]
        case .msi: ["msi"]
        case .squashfs: ["squashfs", "sqfs"]
        case .vhd: ["vhd", "vhdx"]
        case .vmdk: ["vmdk"]
        }
    }

    /// Compresses exactly one file, with no folder structure (gzip, xz, …).
    public var isSingleFile: Bool {
        switch self {
        case .gzip, .bzip2, .xz, .zstd, .lz4, .lzip, .lzma, .compress: true
        default: false
        }
    }

    /// A tar archive inside a compressor, written and read as one step.
    public var isCompressedTar: Bool {
        switch self {
        case .tarGzip, .tarBzip2, .tarXz, .tarZstd, .tarLz4: true
        default: false
        }
    }

    /// Can protect its contents with a password when created.
    public var supportsPassword: Bool {
        switch self {
        case .zip, .sevenZip, .rar: true
        default: false
        }
    }

    /// Formats offered first in the create sheet; the rest are under "More formats".
    public static let common: [ArchiveFormat] = [.zip, .sevenZip, .tarGzip, .tarXz]

    /// The format with `extension` (case-insensitive for everything but ".Z").
    public init?(fileExtension ext: String) {
        let match = ArchiveFormat.allCases.first { format in
            format.extensions.contains { $0 == ext || ($0 != "Z" && $0.lowercased() == ext.lowercased()) }
        }
        guard let match else { return nil }
        self = match
    }
}
