import Foundation

/// The advanced settings each format offers when creating an archive.
///
/// The compression level and password are not here: every format has the level, and the
/// password belongs to `ArchiveFormat.supportsPassword`. What's here is what most people
/// never change, so the create sheet keeps it under "Advanced settings".
///
/// Adding an option: add it here with a stable `id`, read it in the backend that creates
/// the format (`request.value(id)`), and add or reuse a `GuideTopic` for its explanation.
public enum FormatOptions {
    public static func options(for format: ArchiveFormat) -> [FormatOption] {
        switch format {
        case .zip: [zipMethod, zipEncryption]
        case .sevenZip: [sevenZipMethod, dictionary, solid, encryptNames]
        case .tarGzip, .tarBzip2, .tarXz, .tarZstd, .tarLz4: [tarFormat]
        case .iso: [isoVolumeName, isoJoliet, isoRockRidge]
        case .rar: [rarVersion, rarSolid, encryptNames, recoveryRecord, volumeSize]
        default: []
        }
    }

    // MARK: ZIP

    public static let zipMethod = FormatOption(
        id: "zip.method",
        title: "Method",
        summary: "Deflate opens everywhere. The others compress better but need a newer unzip tool.",
        kind: .choice([
            .init("Deflate", "Deflate"),
            .init("Deflate64", "Deflate64"),
            .init("BZip2", "BZip2"),
            .init("LZMA", "LZMA"),
            .init("PPMd", "PPMd"),
        ]),
        guide: "zip-method"
    )

    public static let zipEncryption = FormatOption(
        id: "zip.encryption",
        title: "Encryption",
        summary: "AES-256 is secure. ZipCrypto is weak, but every old tool can open it.",
        kind: .choice([.init("AES256", "AES-256"), .init("ZipCrypto", "ZipCrypto (legacy)")]),
        guide: "zip-encryption",
        needsPassword: true
    )

    // MARK: 7z

    public static let sevenZipMethod = FormatOption(
        id: "7z.method",
        title: "Method",
        summary: "LZMA2 is the best all-rounder. PPMd is better for plain text.",
        kind: .choice([
            .init("LZMA2", "LZMA2"),
            .init("LZMA", "LZMA"),
            .init("PPMd", "PPMd"),
            .init("BZip2", "BZip2"),
            .init("Deflate", "Deflate"),
        ]),
        guide: "7z-method"
    )

    public static let dictionary = FormatOption(
        id: "7z.dictionary",
        title: "Dictionary size",
        summary: "How far back the compressor looks for repeats. Bigger can be smaller, but uses more memory to open.",
        kind: .choice([
            .init("auto", "Automatic"),
            .init("1m", "1 MB"),
            .init("16m", "16 MB"),
            .init("64m", "64 MB"),
            .init("256m", "256 MB"),
        ]),
        guide: "dictionary"
    )

    public static let solid = FormatOption(
        id: "7z.solid",
        title: "Solid archive",
        summary: "Compresses all files as one stream: smaller for many similar files, but slower to open one file.",
        kind: .toggle,
        defaultValue: "on",
        guide: "solid"
    )

    /// Shared by 7z and RAR.
    public static let encryptNames = FormatOption(
        id: "encryptNames",
        title: "Encrypt file names",
        summary: "Hides the list of files too, so the password is needed even to look inside.",
        kind: .toggle,
        guide: "encrypt-names",
        needsPassword: true
    )

    // MARK: Compressed tar

    public static let tarFormat = FormatOption(
        id: "tar.format",
        title: "Tar flavor",
        summary: "POSIX keeps long names and exact times. Use ustar only for very old systems.",
        kind: .choice([.init("pax", "POSIX (pax)"), .init("gnutar", "GNU tar"), .init("ustar", "ustar")]),
        guide: "tar-format"
    )

    // MARK: ISO

    public static let isoVolumeName = FormatOption(
        id: "iso.volumeName",
        title: "Volume name",
        summary: "The disc name shown when the image is mounted.",
        kind: .text(placeholder: "CDROM"),
        guide: "iso"
    )

    public static let isoJoliet = FormatOption(
        id: "iso.joliet",
        title: "Joliet names",
        summary: "Long and non-English file names for Windows.",
        kind: .toggle,
        defaultValue: "on",
        guide: "iso"
    )

    public static let isoRockRidge = FormatOption(
        id: "iso.rockRidge",
        title: "Rock Ridge",
        summary: "Unix names, permissions and times for Mac and Linux.",
        kind: .toggle,
        defaultValue: "on",
        guide: "iso"
    )

    // MARK: RAR (experimental, rars)

    public static let rarVersion = FormatOption(
        id: "rar.version",
        title: "RAR version",
        summary: "RAR 7 compresses best. RAR 5 opens in WinRAR 5 and later. RAR 2.9 opens almost anywhere.",
        kind: .choice([.init("rar7", "RAR 7"), .init("rar5", "RAR 5"), .init("rar29", "RAR 2.9 (RAR4)")]),
        guide: "rar-version"
    )

    /// Off by default, like WinRAR (7z's solid is on by default, like 7-Zip).
    public static let rarSolid = FormatOption(
        id: "rar.solid",
        title: "Solid archive",
        summary: "Compresses all files as one stream: smaller for many similar files, but slower to open one file.",
        kind: .toggle,
        guide: "solid"
    )

    public static let recoveryRecord = FormatOption(
        id: "rar.recovery",
        title: "Recovery record",
        summary: "Extra data that lets a damaged archive be repaired. Makes the file bigger by about that much.",
        kind: .choice([
            .init("0", "None"),
            .init("1", "1%"),
            .init("3", "3%"),
            .init("5", "5%"),
            .init("10", "10%"),
        ]),
        guide: "recovery-record"
    )

    public static let volumeSize = FormatOption(
        id: "rar.volumeSize",
        title: "Split into parts",
        summary: "Writes name.part1.rar, name.part2.rar, … of this size each. RAR 5 and 7 only.",
        kind: .choice([
            .init("0", "Don't split"),
            .init("100m", "100 MB"),
            .init("700m", "700 MB"),
            .init("2g", "2 GB"),
            .init("4g", "4 GB (FAT32)"),
        ]),
        guide: "volumes"
    )

    /// "100m" → 104_857_600. `nil` for "0" or unparseable values.
    public static func byteCount(_ value: String) -> UInt64? {
        let lower = value.lowercased()
        let multiplier: UInt64 = switch lower.last {
        case "k": 1 << 10
        case "m": 1 << 20
        case "g": 1 << 30
        default: 1
        }
        let digits = multiplier == 1 ? lower : String(lower.dropLast())
        guard let number = UInt64(digits), number > 0 else { return nil }
        return number * multiplier
    }
}
