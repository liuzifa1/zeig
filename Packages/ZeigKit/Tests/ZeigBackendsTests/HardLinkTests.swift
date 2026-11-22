import Foundation
import Testing
@testable import ZeigBackends
import ZeigCore

/// Tar stores a hard link's data once, under its first name; the second name is an entry with
/// no data. Extracting it as a regular file used to leave an empty file.
@Suite struct HardLinkTests {
    let service = ArchiveService(settings: RoutingSettings())

    @Test("Hard links get their file's contents", arguments: [ArchiveFormat.tarGzip, .tar])
    func hardLinksKeepTheirContents(format: ArchiveFormat) async throws {
        let scratch = try Scratch()
        let source = scratch.path("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let contents = Data(String(repeating: "linked line\n", count: 200).utf8)
        try contents.write(to: source.appendingPathComponent("original.txt"))
        try FileManager.default.linkItem(at: source.appendingPathComponent("original.txt"), to: source.appendingPathComponent("link.txt"))

        // The system's bsdtar keeps hard links as links, which is what's being tested.
        let archive = scratch.path("links." + format.fileExtension)
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = [format == .tar ? "-cf" : "-czf", archive.path, "-C", source.path, "original.txt", "link.txt"]
        try tar.run()
        tar.waitUntilExit()
        #expect(tar.terminationStatus == 0)

        let listing = try await service.open(archive)
        let folder = try await service.extractToNewFolder(listing)
        for name in ["original.txt", "link.txt"] {
            let extracted = try Data(contentsOf: folder.appendingPathComponent(name))
            #expect(extracted == contents, "\(name) via \(listing.backend): \(extracted.count) bytes instead of \(contents.count)")
        }
    }
}
