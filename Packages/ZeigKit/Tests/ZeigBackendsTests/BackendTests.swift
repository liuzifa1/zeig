import Foundation
import Testing
@testable import ZeigBackends
import ZeigCore

/// The capability tables in ZeigCore must match what the libraries actually do.
@Suite struct CapabilityTests {
    @Test func sevenZipWritesExactlyTheTable() {
        let writable = Set(SevenZipBackend.handlers.filter(\.canWrite).map(\.name))
        let table = Set(BackendCapabilities.sevenZip.writes.compactMap { SevenZipBackend.handlerNames(for: $0) })
        #expect(writable == table)
    }

    @Test("7-Zip has a handler for every format it claims to read", arguments: Array(BackendCapabilities.sevenZip.reads))
    func sevenZipHasHandlers(format: ArchiveFormat) throws {
        let names = try #require(SevenZipBackend.handlerNames(for: format)).split(separator: ",").map(String.init)
        let available = Set(SevenZipBackend.handlers.map(\.name))
        #expect(names.allSatisfy(available.contains), "\(format): \(names)")
    }

    @Test func versions() {
        #expect(SevenZipBackend().version == "26.05")
        #expect(LibArchiveBackend().version == "3.8.10")
        #expect(RarsBackend().version == "0.12.3")
        #expect(LibArchiveBackend().versionDetails.contains("liblzma"))
        #expect(LibArchiveBackend().versionDetails.contains("libzstd"))
    }
}

/// Files made by one library must open in the other: they're interchangeable readers.
@Suite struct CrossBackendTests {
    @Test("7-Zip's output opens in libarchive", arguments: [ArchiveFormat.zip, .sevenZip, .tar])
    func sevenZipToLibArchive(format: ArchiveFormat) throws {
        let scratch = try Scratch()
        let tree = try scratch.makeTree()
        let archive = scratch.path("x." + format.fileExtension)
        _ = try SevenZipBackend().create(PackRequest(destination: archive, sources: [tree], format: format), progress: .none)
        let out = scratch.path("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try LibArchiveBackend().extract(archive, format: format, to: out, entries: nil, password: nil, progress: .none)
        let actual = normalized(filesOnly(try snapshot(out.appendingPathComponent("tree"))))

        let expected = normalized(filesOnly(try snapshot(tree)))

        #expect(actual == expected, "\(differences(actual, expected))")
    }

    @Test("libarchive's output opens in 7-Zip", arguments: [ArchiveFormat.zip, .sevenZip, .tar, .iso, .cpio, .xar])
    func libArchiveToSevenZip(format: ArchiveFormat) throws {
        let scratch = try Scratch()
        let tree = try scratch.makeTree()
        let archive = scratch.path("x." + format.fileExtension)
        _ = try LibArchiveBackend().create(PackRequest(destination: archive, sources: [tree], format: format), progress: .none)
        try SevenZipBackend().test(archive, format: format, password: nil, progress: .none)
    }

    @Test("rars output opens in 7-Zip", arguments: ["rar7", "rar5", "rar29"])
    func rarsToSevenZip(version: String) throws {
        let scratch = try Scratch()
        let tree = try scratch.makeTree()
        if version == "rar29" {
            // Non-ASCII names are a known rars RAR 2.9 limitation (rar29NonASCIINamesAreFlagged).
            try FileManager.default.removeItem(at: tree.appendingPathComponent("naïve résumé ✓.txt"))
        }
        let archive = scratch.path("x.rar")
        _ = try RarsBackend().create(
            PackRequest(destination: archive, sources: [tree], format: .rar, advanced: [FormatOptions.rarVersion.id: version]),
            progress: .none
        )
        let out = scratch.path("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try SevenZipBackend().extract(archive, format: .rar, to: out, entries: nil, password: nil, progress: .none)
        let actual = normalized(filesOnly(try snapshot(out.appendingPathComponent("tree"))))

        let expected = normalized(filesOnly(try snapshot(tree)))

        #expect(actual == expected, "\(differences(actual, expected))")
    }

    /// rars writes RAR 2.9 names as raw UTF-8 without RAR's Unicode name field, so 7-Zip
    /// reads non-ASCII names in a legacy code page. The data is intact; the service's check
    /// must flag the names.
    @Test func rar29NonASCIINamesAreFlagged() async throws {
        let scratch = try Scratch()
        let tree = try scratch.makeTree()
        let service = ArchiveService(settings: RoutingSettings(rarsEnabled: true))
        let result = try await service.create(PackRequest(
            destination: scratch.path("old.rar"), sources: [tree], format: .rar,
            advanced: [FormatOptions.rarVersion.id: "rar29"]
        ))
        guard case .failed(.corrupt(let detail)) = result.verification else {
            Issue.record("expected a failed name check, got \(result.verification)")
            return
        }
        #expect(detail.contains("naïve"))
    }

    @Test func rarsSplitVolumesOpenInBothReaders() async throws {
        let scratch = try Scratch()
        let big = try scratch.makeFile("big.bin", size: 400_000)
        let archive = scratch.path("split.rar")
        let request = PackRequest(
            destination: archive, sources: [big], format: .rar, level: .store,
            advanced: [FormatOptions.volumeSize.id: "100k"]
        )
        let written = try RarsBackend().create(request, progress: .none)
        #expect(written.count >= 4)
        #expect(written.first?.lastPathComponent == "split.part1.rar")

        for backend in [BackendID.sevenZip, .rars] {
            let out = scratch.path("out-\(backend)")
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try ArchiveService.backend(backend).extract(written[0], format: .rar, to: out, entries: nil, password: nil, progress: .none)
            #expect(try Data(contentsOf: out.appendingPathComponent("big.bin")) == Data(contentsOf: big), "\(backend)")
        }
    }

    @Test func libArchiveIsTheFallbackFor7ZipFailures() async throws {
        // A compressed tar named as if it were a plain .gz: 7-Zip would show one .tar
        // inside. The router sends it to libarchive because of the name… so name it
        // ambiguously and check the service still opens it.
        let scratch = try Scratch()
        let tree = try scratch.makeTree()
        let archive = scratch.path("x.tar.zst")
        _ = try LibArchiveBackend().create(PackRequest(destination: archive, sources: [tree], format: .tarZstd), progress: .none)
        let renamed = scratch.path("mystery.bin")
        try FileManager.default.moveItem(at: archive, to: renamed)
        let listing = try await ArchiveService().open(renamed)
        #expect(!listing.entries.isEmpty)
    }
}

@Suite struct OptionMappingTests {
    @Test func sevenZipProperties() {
        let request = PackRequest(
            destination: URL(fileURLWithPath: "/x.7z"), sources: [], format: .sevenZip, level: .ultra, password: "pw",
            advanced: [FormatOptions.dictionary.id: "64m", FormatOptions.encryptNames.id: "on", FormatOptions.solid.id: "off"]
        )
        let properties = Dictionary(uniqueKeysWithValues: SevenZipBackend.properties(for: request))
        #expect(properties == ["x": "9", "m": "LZMA2", "d": "64m", "s": "off", "he": "on"])
    }

    @Test func storeSkipsTheMethod() {
        let request = PackRequest(destination: URL(fileURLWithPath: "/x.zip"), sources: [], format: .zip, level: .store)
        #expect(SevenZipBackend.properties(for: request).map(\.0) == ["x"])
    }

    @Test func rarsOptions() {
        let request = PackRequest(
            destination: URL(fileURLWithPath: "/x.rar"), sources: [], format: .rar, level: .maximum, password: "pw",
            advanced: [
                FormatOptions.rarVersion.id: "rar29", FormatOptions.recoveryRecord.id: "5",
                FormatOptions.volumeSize.id: "100m", FormatOptions.encryptNames.id: "on",
            ]
        )
        let options = RarsBackend.options(for: request)
        #expect(options.version == .rar29)
        #expect(options.level == 4)
        #expect(options.recoveryPercent == 5)
        #expect(options.volumeSize == nil, "RAR 2.9 can't be split by rars")
        #expect(options.encryptHeaders)
    }

    @Test func zstdLevels() {
        #expect(CompressionLevel.allCases.map { LibArchiveBackend.filterLevel(.zstd, $0) } == [1, 1, 2, 3, 9, 19])
        #expect(LibArchiveBackend.filterLevel(.compress, .ultra) == nil)
    }
}

/// What the engines report about an archive as a whole (the Info sheet's Compression section).
@Suite struct ArchiveInfoTests {
    @Test func sevenZipReportsMethodAndSolid() async throws {
        let scratch = try Scratch()
        let tree = try scratch.makeTree()
        let archive = scratch.path("x.7z")
        let service = ArchiveService()
        _ = try await service.create(PackRequest(destination: archive, sources: [tree], format: .sevenZip))
        let listing = try await service.open(archive)
        #expect(listing.info.formatName == "7z")
        #expect(listing.info.method?.contains("LZMA2") == true)
        #expect(listing.info.isSolid == true)
        let stats = listing.statistics
        #expect(stats.fileCount == 5)
        #expect(stats.archiveSize > 0 && stats.archiveSize < stats.originalSize)
    }

    @Test func zipReportsTheFirstEntrysMethod() async throws {
        let scratch = try Scratch()
        let archive = scratch.path("x.zip")
        _ = try await ArchiveService().create(PackRequest(destination: archive, sources: [try scratch.makeTree()], format: .zip))
        let method = try await ArchiveService().open(archive).info.method
        #expect(method?.contains("Deflate") == true, "method: \(method ?? "nil")")
    }

    @Test func libArchiveReportsFormatAndFilter() async throws {
        let scratch = try Scratch()
        let archive = scratch.path("x.tar.gz")
        _ = try await ArchiveService().create(PackRequest(destination: archive, sources: [try scratch.makeTree()], format: .tarGzip))
        let info = try await ArchiveService().open(archive).info
        #expect(info.method == "gzip")
        #expect(info.formatName?.lowercased().contains("tar") == true || info.formatName?.lowercased().contains("pax") == true)
    }
}
