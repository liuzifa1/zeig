import Foundation
import Testing
@testable import ZeigBackends
import ZeigCore

/// Create → open → extract → compare, through `ArchiveService`, for every format Zeig
/// creates. This exercises the real libraries, the router and the C bridges together.
@Suite struct RoundTripTests {
    let service = ArchiveService(settings: RoutingSettings(rarsEnabled: true))

    static let multiFileFormats = BackendRouter(settings: RoutingSettings(rarsEnabled: true))
        .creatableFormats.filter { !$0.isSingleFile }
    static let singleFileFormats = ArchiveFormat.allCases.filter { $0.isSingleFile }

    @Test("Folders round-trip", arguments: multiFileFormats)
    func folderRoundTrip(format: ArchiveFormat) async throws {
        let scratch = try Scratch()
        let tree = try scratch.makeTree()
        let archive = scratch.path("out." + format.fileExtension)

        let result = try await service.create(PackRequest(destination: archive, sources: [tree], format: format))
        #expect(result.files == [archive])
        if format == .rar { #expect(result.verification == .passed) }

        let listing = try await service.open(archive)
        #expect(listing.backend == service.router.opener(for: format))
        #expect(!listing.usedFallback)
        #expect(listing.entries.contains { $0.path.hasSuffix("sub/deeper/binary.bin") })

        let folder = try await service.extractToNewFolder(listing)
        let original = normalized(try snapshot(scratch.path("tree")))
        let extracted = normalized(try snapshot(folder.appendingPathComponent("tree")))
        // ISO 9660 doesn't keep empty folders; compare files there.
        if format == .iso {
            #expect(filesOnly(extracted) == filesOnly(original), "\(differences(filesOnly(extracted), filesOnly(original)))")
        } else {
            #expect(extracted == original, "\(differences(extracted, original))")
        }
    }

    @Test("Single files round-trip", arguments: singleFileFormats)
    func singleFileRoundTrip(format: ArchiveFormat) async throws {
        let scratch = try Scratch()
        let file = try scratch.makeFile("data.bin")
        let archive = scratch.path("data.bin." + format.fileExtension)
        _ = try await service.create(PackRequest(destination: archive, sources: [file], format: format))

        let listing = try await service.open(archive)
        #expect(listing.entries.count == 1)
        #expect(listing.entries.first?.path == "data.bin")
        let folder = try await service.extractToNewFolder(listing)
        #expect(try Data(contentsOf: folder.appendingPathComponent("data.bin")) == Data(contentsOf: file))
    }

    @Test func singleFileFormatsRefuseFolders() async throws {
        let scratch = try Scratch()
        let tree = try scratch.makeTree()
        await #expect(throws: ArchiveError.self) {
            _ = try await service.create(PackRequest(destination: scratch.path("x.gz"), sources: [tree], format: .gzip))
        }
        await #expect(throws: ArchiveError.self) {
            _ = try await service.create(PackRequest(destination: scratch.path("x.zst"), sources: [tree], format: .zstd))
        }
    }

    @Test("Every level works", arguments: CompressionLevel.allCases)
    func levels(level: CompressionLevel) async throws {
        let scratch = try Scratch()
        let tree = try scratch.makeTree()
        for format in [ArchiveFormat.zip, .sevenZip, .tarXz, .tarZstd] {
            let archive = scratch.path("\(level)." + format.fileExtension)
            do {
                _ = try await service.create(PackRequest(destination: archive, sources: [tree], format: format, level: level))
                try await service.test(try await service.open(archive))
            } catch {
                Issue.record("\(format) at \(level): \(error)")
            }
        }
    }

    @Test func extractingSomeEntries() async throws {
        let scratch = try Scratch()
        let tree = try scratch.makeTree()
        for format in [ArchiveFormat.zip, .tarGzip, .rar] {
            let archive = scratch.path("some." + format.fileExtension)
            _ = try await service.create(PackRequest(destination: archive, sources: [tree], format: format))
            let listing = try await service.open(archive)
            let chosen = listing.entries.filter { $0.path.hasSuffix("hello.txt") }
            #expect(chosen.count == 1)
            let out = scratch.path("some-\(format.rawValue)")
            try await service.extract(listing, entries: chosen, to: out)
            let files = try snapshot(out).filter { !$0.key.hasSuffix("/") }
            #expect(files == ["tree/hello.txt": Data("hello world\n".utf8)], "\(format)")
        }
    }

    @Test func extractionFolderNamesDontCollide() async throws {
        let scratch = try Scratch()
        let file = try scratch.makeFile("a.txt", size: 10)
        let archive = scratch.path("a.zip")
        _ = try await service.create(PackRequest(destination: archive, sources: [file], format: .zip))
        let listing = try await service.open(archive)
        let first = try await service.extractToNewFolder(listing)
        let second = try await service.extractToNewFolder(listing)
        #expect(first.lastPathComponent == "a")
        #expect(second.lastPathComponent == "a 2")
    }
}
