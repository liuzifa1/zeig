import Foundation

/// Works out an archive's format from its name and its first bytes.
///
/// The contents win over the name: a ".zip" that starts with a 7z signature is 7z. The name
/// only decides what the bytes can't, such as gzip vs tar.gz (the same signature). `nil`
/// means "not a format Zeig names"; the backends may still recognize it.
public enum FormatDetector {
    /// Bytes read from the start of a file: enough for tar's signature at 257 and ISO's at
    /// 32769.
    public static let headerLength = 32 * 1024 + 8

    public static func detect(_ url: URL) -> ArchiveFormat? {
        let header = (try? FileHandle(forReadingFrom: url)).flatMap { handle in
            defer { try? handle.close() }
            return try? handle.read(upToCount: headerLength)
        } ?? Data()
        return detect(name: url.lastPathComponent, header: header)
    }

    public static func detect(name: String, header: Data) -> ArchiveFormat? {
        let byName = format(forName: name)
        guard let bySignature = format(forSignature: header) else { return byName }
        // A compressor's signature plus a tar name is a compressed tar.
        if let byName, byName.isCompressedTar, compressor(of: byName) == bySignature {
            return byName
        }
        // Debian packages are ar archives; keep the more specific name.
        if bySignature == .ar, byName == .deb { return .deb }
        return bySignature
    }

    /// The format a file name suggests, from the longest matching extension. Split RAR
    /// volumes ("name.part2.rar") count as RAR.
    public static func format(forName name: String) -> ArchiveFormat? {
        let lower = name.lowercased()
        var best: (format: ArchiveFormat, length: Int)?
        for format in ArchiveFormat.allCases {
            for ext in format.extensions {
                let matches = ext == "Z" ? name.hasSuffix(".Z") : lower.hasSuffix("." + ext.lowercased())
                if matches, ext.count > (best?.length ?? 0) {
                    best = (format, ext.count)
                }
            }
        }
        return best?.format
    }

    /// The format whose magic bytes start `header`, for the formats with a fixed signature.
    public static func format(forSignature header: Data) -> ArchiveFormat? {
        let bytes = [UInt8](header.prefix(headerLength))
        func starts(with signature: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + signature.count && Array(bytes[offset..<offset + signature.count]) == signature
        }
        if starts(with: [0x50, 0x4B, 0x03, 0x04]) || starts(with: [0x50, 0x4B, 0x05, 0x06]) { return .zip }
        if starts(with: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return .sevenZip }
        if starts(with: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]) { return .rar }  // RAR 1.5–4 and 5+
        if starts(with: [0x1F, 0x8B]) { return .gzip }
        if starts(with: [0x42, 0x5A, 0x68]) { return .bzip2 }
        if starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return .xz }
        if starts(with: [0x28, 0xB5, 0x2F, 0xFD]) { return .zstd }
        if starts(with: [0x04, 0x22, 0x4D, 0x18]) { return .lz4 }
        if starts(with: [0x4C, 0x5A, 0x49, 0x50]) { return .lzip }
        if starts(with: [0x1F, 0x9D]) { return .compress }
        if starts(with: [0x4D, 0x53, 0x43, 0x46]) { return .cab }
        if starts(with: [0x78, 0x61, 0x72, 0x21]) { return .xar }
        if starts(with: Array("!<arch>\n".utf8)) { return .ar }
        if starts(with: Array("070707".utf8)) || starts(with: Array("070701".utf8))
            || starts(with: Array("070702".utf8)) || starts(with: [0xC7, 0x71]) { return .cpio }
        if starts(with: [0xED, 0xAB, 0xEE, 0xDB]) { return .rpm }
        if starts(with: Array("MSWIM\0\0\0".utf8)) { return .wim }
        if starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) { return .msi }
        if starts(with: Array("ustar".utf8), at: 257) { return .tar }
        if starts(with: Array("CD001".utf8), at: 32769) { return .iso }
        return nil
    }

    /// For a compressed tar, the single-file format of its outer layer.
    public static func compressor(of format: ArchiveFormat) -> ArchiveFormat? {
        switch format {
        case .tarGzip: .gzip
        case .tarBzip2: .bzip2
        case .tarXz: .xz
        case .tarZstd: .zstd
        case .tarLz4: .lz4
        default: nil
        }
    }
}
