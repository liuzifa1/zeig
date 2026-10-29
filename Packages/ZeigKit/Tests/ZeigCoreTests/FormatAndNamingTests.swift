import Foundation
import Testing
import ZeigCore

@Suite struct FormatDetectorTests {
    @Test(arguments: [
        ("photos.zip", ArchiveFormat.zip),
        ("backup.tar.gz", .tarGzip),
        ("backup.TGZ", .tarGzip),
        ("notes.txt.gz", .gzip),
        ("set.part2.rar", .rar),
        ("disk.iso", .iso),
        ("old.Z", .compress),
        ("pkg.deb", .deb),
    ])
    func namesMapToFormats(name: String, format: ArchiveFormat) {
        #expect(FormatDetector.format(forName: name) == format)
    }

    @Test func unknownNamesAreNil() {
        #expect(FormatDetector.format(forName: "readme.txt") == nil)
        #expect(FormatDetector.format(forName: "archive") == nil)
    }

    @Test func contentsBeatTheName() {
        let sevenZip = Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00, 0x04])
        #expect(FormatDetector.detect(name: "renamed.zip", header: sevenZip) == .sevenZip)
    }

    @Test func gzipSignatureWithTarNameIsCompressedTar() {
        let gzip = Data([0x1F, 0x8B, 0x08, 0x00])
        #expect(FormatDetector.detect(name: "src.tar.gz", header: gzip) == .tarGzip)
        #expect(FormatDetector.detect(name: "log.gz", header: gzip) == .gzip)
    }

    @Test func tarSignatureAtOffset257() {
        var header = Data(count: 512)
        header.replaceSubrange(257..<262, with: Array("ustar".utf8))
        #expect(FormatDetector.format(forSignature: header) == .tar)
    }

    @Test func emptyHeaderFallsBackToName() {
        #expect(FormatDetector.detect(name: "a.7z", header: Data()) == .sevenZip)
    }
}

@Suite struct FileNamingTests {
    @Test(arguments: [
        ("photos.zip", "photos", "zip"),
        ("backup.tar.gz", "backup", "tar.gz"),
        ("a.b.zip", "a.b", "zip"),
        ("notes", "notes", ""),
        ("report.pdf", "report", "pdf"),
        (".hidden", ".hidden", ""),
    ])
    func splitsCompoundExtensions(name: String, stem: String, ext: String) {
        let parts = FileNaming.split(name)
        #expect(parts.stem == stem)
        #expect(parts.extension == ext)
    }

    @Test func uniqueAddsANumberBeforeTheExtension() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("backup.tar.gz")
        #expect(FileNaming.unique(first) == first)
        FileManager.default.createFile(atPath: first.path, contents: Data())
        #expect(FileNaming.unique(first).lastPathComponent == "backup 2.tar.gz")
        FileManager.default.createFile(atPath: folder.appendingPathComponent("backup 2.tar.gz").path, contents: Data())
        #expect(FileNaming.unique(first).lastPathComponent == "backup 3.tar.gz")
    }

    @Test func archiveNames() {
        let file = URL(fileURLWithPath: "/x/report.pdf")
        #expect(FileNaming.archiveName(for: [file], format: .zip) == "report.zip")
        #expect(FileNaming.archiveName(for: [file], format: .gzip) == "report.pdf.gz")
        #expect(FileNaming.archiveName(for: [file, file], format: .sevenZip) == "Archive.7z")
    }

    @Test func extractionFolders() {
        #expect(FileNaming.extractionFolder(for: URL(fileURLWithPath: "/x/photos.tar.gz")).lastPathComponent == "photos")
        #expect(FileNaming.extractionFolder(for: URL(fileURLWithPath: "/x/set.part1.rar")).lastPathComponent == "set")
    }

    @Test func decompressedNames() {
        #expect(FileNaming.decompressedName(for: URL(fileURLWithPath: "/x/log.txt.gz")) == "log.txt")
        #expect(FileNaming.decompressedName(for: URL(fileURLWithPath: "/x/src.tgz")) == "src.tar")
    }
}

@Suite struct EntryAndOptionTests {
    @Test(arguments: [
        ("folder/file.txt", "folder/file.txt"),
        ("/etc/passwd", "etc/passwd"),
        ("../../escape.txt", "escape.txt"),
        ("a/./b/../c", "a/b/c"),
        ("windows\\style\\path", "windows/style/path"),
    ])
    func sanitizedPathsStayInside(path: String, expected: String) {
        #expect(ArchiveEntry.sanitize(path) == expected)
    }

    @Test func nothingLeftIsNil() {
        #expect(ArchiveEntry.sanitize("../..") == nil)
        #expect(ArchiveEntry.sanitize("/") == nil)
    }

    @Test func levelsSpreadOverEachScale() {
        #expect(CompressionLevel.allCases.map { $0.level(in: 0...9) } == [0, 1, 3, 5, 7, 9])
        #expect(CompressionLevel.allCases.map { $0.level(in: 0...5) } == [0, 1, 2, 3, 4, 5])
    }

    @Test func byteCounts() {
        #expect(FormatOptions.byteCount("100m") == 100 << 20)
        #expect(FormatOptions.byteCount("4g") == 4 << 30)
        #expect(FormatOptions.byteCount("0") == nil)
        #expect(FormatOptions.byteCount("junk") == nil)
    }

    @Test func requestsFallBackToOptionDefaults() {
        let request = PackRequest(destination: URL(fileURLWithPath: "/x.7z"), sources: [], format: .sevenZip)
        #expect(request.value(FormatOptions.sevenZipMethod.id) == "LZMA2")
        #expect(request.isOn(FormatOptions.solid.id))
        #expect(!request.isOn(FormatOptions.encryptNames.id))
    }

    @Test func passwordsOnlyWhereSupported() {
        var request = PackRequest(destination: URL(fileURLWithPath: "/x.tar"), sources: [], format: .tar, password: "pw")
        #expect(request.effectivePassword == nil)
        request.format = .zip
        #expect(request.effectivePassword == "pw")
        request.password = ""
        #expect(request.effectivePassword == nil)
    }

    @Test func everyOptionHasAGuideTopic() {
        for format in ArchiveFormat.allCases {
            for option in FormatOptions.options(for: format) {
                #expect(GuideTopic.topic(option.guide) != nil, "\(option.id) → \(option.guide)")
            }
        }
    }
}
