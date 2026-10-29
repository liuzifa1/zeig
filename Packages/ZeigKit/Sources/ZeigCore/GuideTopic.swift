import Foundation

/// A full explanation of a format or setting, for Settings → Format Guide and the ⓘ next to
/// each advanced setting. The create sheet shows the one-line `FormatOption.summary`; this is
/// the "still confused" version.
public struct GuideTopic: Sendable, Identifiable, Hashable {
    public typealias ID = String

    public var id: ID
    public var title: String
    /// One sentence for lists.
    public var summary: String
    /// Paragraphs.
    public var body: [String]

    public init(id: ID, title: String, summary: String, body: [String]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.body = body
    }

    public static func topic(_ id: ID) -> GuideTopic? { all.first { $0.id == id } }

    /// Topics in the order the guide lists them: formats, then settings.
    public static let all: [GuideTopic] = formats + settings

    public static let formats: [GuideTopic] = [
        GuideTopic(
            id: "choosing-format",
            title: "Which format should I use?",
            summary: "ZIP to share, 7z to save space, tar.gz or tar.xz for Mac and Linux.",
            body: [
                "ZIP opens on every phone and computer without extra apps. Use it when you send files to someone else.",
                "7z usually makes smaller files than ZIP, especially for many files or big documents, and has strong AES-256 encryption. Windows and Mac need an app such as 7-Zip or Zeig to open it.",
                "tar.gz and tar.xz are the usual formats on Mac and Linux. They keep Unix permissions and are good for code and backups. tar.xz is smaller, tar.gz is faster. They can't be encrypted.",
                "The single-file formats (GZIP, XZ, Zstandard, …) compress exactly one file and keep no folders. Pick them only when a tool asks for that format.",
            ]
        ),
        GuideTopic(
            id: "single-file",
            title: "Single-file formats",
            summary: "GZIP, BZIP2, XZ, Zstandard, LZ4, Lzip, LZMA and .Z hold one file only.",
            body: [
                "These formats are compressors, not archives: they squeeze one stream of bytes and don't store folders or several files.",
                "To compress a folder with one of them, choose its tar version instead (tar.gz, tar.xz, tar.zst, …). Tar first packs the folder into one file, then the compressor shrinks it.",
            ]
        ),
        GuideTopic(
            id: "rar-experimental",
            title: "Creating RAR archives (experimental)",
            summary: "Done by rars, an independent open-source RAR implementation. Off by default.",
            body: [
                "RAR is a proprietary format, and the official RAR software can't be built into apps. Zeig creates RAR archives with rars, an independent open-source implementation of the format (github.com/bitplane/rars).",
                "rars is young. Its author says it needs more testing at volume, and it is slower and compresses slightly less than WinRAR. Treat archives it makes as experimental: keep your originals until you have checked the archive opens where you need it.",
                "To catch problems early, Zeig opens every RAR archive rars creates with 7-Zip, a separate RAR reader, and tells you if the check fails.",
                "Opening RAR archives normally uses 7-Zip, which is well tested. You can also let rars open them, to try it out.",
                "RAR is a trademark of win.rar GmbH. Zeig and rars aren't affiliated with it.",
            ]
        ),
    ]

    public static let settings: [GuideTopic] = [
        GuideTopic(
            id: "compression-level",
            title: "Compression level",
            summary: "Higher levels make smaller files but take longer.",
            body: [
                "Store copies files without compressing them: fastest, and the right choice for photos, videos and music, which are compressed already.",
                "Normal is a good balance. Maximum and Ultra save a few percent more and can take several times longer; Ultra also needs more memory to open the archive.",
                "The level only changes the size and speed. Any level opens the same way.",
            ]
        ),
        GuideTopic(
            id: "password",
            title: "Passwords",
            summary: "ZIP, 7z and RAR can be protected with a password.",
            body: [
                "With a password, the contents can't be read without it. There's no way to recover a lost password, Zeig doesn't store it, and nobody can reset it.",
                "7z and RAR use AES-256 encryption. ZIP also uses AES-256 by default; see ZIP encryption for older tools.",
                "The file names stay visible unless you also turn on Encrypt file names (7z and RAR).",
            ]
        ),
        GuideTopic(
            id: "encrypt-names",
            title: "Encrypt file names",
            summary: "Hide the list of files, not just their contents.",
            body: [
                "Normally anyone can see the names and sizes of the files in a protected archive, and only opening a file needs the password.",
                "With this on, the password is needed even to see what's inside. Available for 7z and RAR; ZIP can't do it.",
            ]
        ),
        GuideTopic(
            id: "zip-method",
            title: "ZIP method",
            summary: "How ZIP compresses each file.",
            body: [
                "Deflate is the original ZIP method. Every tool, including the ones built into Windows, macOS, iOS and Android, opens it.",
                "Deflate64, BZip2, LZMA and PPMd compress better, but some built-in unzip tools (Windows Explorer, older Macs) can't open them. Use them only if the other side has 7-Zip or similar.",
            ]
        ),
        GuideTopic(
            id: "zip-encryption",
            title: "ZIP encryption",
            summary: "AES-256 is strong; ZipCrypto is weak but very compatible.",
            body: [
                "AES-256 is modern, strong encryption. It opens in 7-Zip, WinRAR, Keka and Zeig, but not in some built-in unzip tools, such as Windows Explorer's.",
                "ZipCrypto is the original ZIP encryption. Every tool supports it, but it can be broken with freely available software. Use it only to keep files away from casual eyes, never for anything sensitive.",
            ]
        ),
        GuideTopic(
            id: "7z-method",
            title: "7z method",
            summary: "The compression algorithm inside a 7z archive.",
            body: [
                "LZMA2 is 7-Zip's default and best in most cases. It can use several processor cores.",
                "LZMA is LZMA2's predecessor: similar size, one core only. Choose it for very old 7-Zip versions.",
                "PPMd is often smaller for plain text (logs, source code, books) and worse for everything else.",
                "BZip2 and Deflate are here for compatibility; they make bigger files.",
            ]
        ),
        GuideTopic(
            id: "dictionary",
            title: "Dictionary size",
            summary: "How much recent data the compressor remembers while looking for repeats.",
            body: [
                "Compressors save space by spotting data they've seen before. The dictionary is how far back they look.",
                "A bigger dictionary helps when similar data is far apart, such as many copies of one library in a big folder. It also means more memory to open the archive: an archive with a 256 MB dictionary needs about 256 MB free on the device that opens it.",
                "Automatic picks a size to match the compression level, which is right almost always.",
            ]
        ),
        GuideTopic(
            id: "solid",
            title: "Solid archives",
            summary: "All files compressed as one continuous stream.",
            body: [
                "In a solid archive, files are compressed one after another as if they were one big file. Similar files (many small text files, photos of documents) then compress much better, because each one benefits from the ones before.",
                "The cost: to open the last file, everything before it has to be decompressed first, and damage anywhere can make the rest of the archive unreadable.",
                "Good for backups you'll extract all at once. Less good for big archives you'll take single files out of.",
            ]
        ),
        GuideTopic(
            id: "tar-format",
            title: "Tar flavor",
            summary: "Different tar dialects, all opened by modern tools.",
            body: [
                "POSIX (pax) is the modern standard. It keeps long file names, non-English names, large files and exact times.",
                "GNU tar is what Linux tools wrote for years; it's as capable for most purposes.",
                "ustar is the old standard: file names over 100 characters and files over 8 GB don't fit. Use it only for very old systems.",
            ]
        ),
        GuideTopic(
            id: "iso",
            title: "ISO disc images",
            summary: "An image of a CD or DVD file system.",
            body: [
                "An ISO is what a disc would contain, as one file. Computers and virtual machines can mount it like a drive.",
                "The volume name is the disc's label. Joliet adds long and Unicode names for Windows, and Rock Ridge adds Unix permissions and names for Mac and Linux. Keep both on unless the image is for a device that rejects them.",
            ]
        ),
        GuideTopic(
            id: "rar-version",
            title: "RAR version",
            summary: "Which generation of the RAR format to write.",
            body: [
                "RAR 7 is the current format and allows the largest dictionaries. It opens in WinRAR 7 and later; other tools may need a recent version.",
                "RAR 5 is the same container with smaller dictionaries. It opens in WinRAR 5 and later and in most other tools.",
                "RAR 2.9 (often called RAR4) is the older format almost every tool can open. It has weaker encryption (AES-128) and smaller dictionaries than RAR 5.",
            ]
        ),
        GuideTopic(
            id: "recovery-record",
            title: "Recovery record",
            summary: "Redundant data that can repair a damaged archive.",
            body: [
                "A recovery record adds repair data to the archive, a bit like the error correction on a CD. If part of the file is damaged later (a bad download, a failing drive), WinRAR or rars can rebuild the damaged part, up to about the size of the record.",
                "It makes the archive bigger by roughly the chosen percentage. Worth it for long-term storage; not needed for files you'll extract soon.",
            ]
        ),
        GuideTopic(
            id: "volumes",
            title: "Split archives",
            summary: "One archive in several files of a fixed size.",
            body: [
                "Splitting writes name.part1.rar, name.part2.rar and so on, each at most the chosen size. Use it when a service or a FAT32 drive limits file size (4 GB).",
                "Keep all parts together in one folder. To open the archive, open the first part; the others are found automatically.",
            ]
        ),
    ]
}
