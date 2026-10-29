import CLibArchive
import Foundation
import Testing
@testable import ZeigBackends
import ZeigCore

@Suite struct PasswordTests {
    let service = ArchiveService(settings: RoutingSettings(rarsEnabled: true))

    @Test("Encrypted names need the password to list", arguments: [ArchiveFormat.sevenZip, .rar])
    func encryptedNames(format: ArchiveFormat) async throws {
        let scratch = try Scratch()
        let tree = try scratch.makeTree()
        let archive = scratch.path("secret." + format.fileExtension)
        let request = PackRequest(
            destination: archive, sources: [tree], format: format, password: "correct horse",
            advanced: [FormatOptions.encryptNames.id: "on"]
        )
        let result = try await service.create(request)
        if format == .rar { #expect(result.verification == .passed) }

        await #expect(throws: ArchiveError.passwordRequired) { _ = try await service.open(archive) }
        await #expect(throws: ArchiveError.wrongPassword) { _ = try await service.open(archive, password: "wrong") }
        let listing = try await service.open(archive, password: "correct horse")
        let folder = try await service.extractToNewFolder(listing, password: "correct horse")
        let actual = normalized(try snapshot(folder.appendingPathComponent("tree")))

        let expected = normalized(try snapshot(tree))

        #expect(actual == expected, "\(differences(actual, expected))")
    }

    @Test("Encrypted contents need the password to extract", arguments: ["AES256", "ZipCrypto"])
    func zipEncryption(method: String) async throws {
        let scratch = try Scratch()
        let tree = try scratch.makeTree()
        let archive = scratch.path("locked.zip")
        _ = try await service.create(PackRequest(
            destination: archive, sources: [tree], format: .zip, password: "pw",
            advanced: [FormatOptions.zipEncryption.id: method]
        ))
        // Names are visible, contents aren't.
        let listing = try await service.open(archive)
        #expect(listing.entries.contains { $0.isEncrypted })
        await #expect(throws: ArchiveError.self) { _ = try await service.extractToNewFolder(listing) }
        await #expect(throws: ArchiveError.wrongPassword) { _ = try await service.extractToNewFolder(listing, password: "nope") }
        let folder = try await service.extractToNewFolder(listing, password: "pw")
        let actual = normalized(try snapshot(folder.appendingPathComponent("tree")))

        let expected = normalized(try snapshot(tree))

        #expect(actual == expected, "\(differences(actual, expected))")
    }
}

/// Archives with "../" or absolute paths must never write outside the extraction folder
/// ("zip slip"). Built with libarchive, which writes whatever names it's given.
@Suite struct PathTraversalTests {
    static let hostileNames = ["../../escaped.txt", "/absolute.txt", "ok/../../../up.txt", "fine.txt"]

    func makeHostileArchive(_ url: URL, format: ArchiveFormat) throws {
        let writer = try #require(archive_write_new())
        defer { archive_write_free(writer) }
        switch format {
        case .zip: archive_write_set_format_zip(writer)
        case .tar: archive_write_set_format_pax_restricted(writer)
        case .sevenZip: archive_write_set_format_7zip(writer)
        default: Issue.record("unsupported \(format)")
        }
        #expect(archive_write_open_filename(writer, url.path) == ARCHIVE_OK)
        for name in Self.hostileNames {
            let entry = archive_entry_new()
            defer { archive_entry_free(entry) }
            archive_entry_set_pathname(entry, name)
            archive_entry_set_filetype(entry, 0o100000)
            archive_entry_set_perm(entry, 0o644)
            archive_entry_set_size(entry, 5)
            archive_write_header(writer, entry)
            archive_write_data(writer, "pwned", 5)
        }
        archive_write_close(writer)
    }

    @Test("No backend writes outside the destination", arguments: [
        (ArchiveFormat.zip, BackendID.sevenZip), (.zip, .libArchive),
        (.tar, .sevenZip), (.tar, .libArchive),
        (.sevenZip, .sevenZip), (.sevenZip, .libArchive),
    ])
    func staysInside(format: ArchiveFormat, backend: BackendID) throws {
        let scratch = try Scratch()
        let archive = scratch.path("hostile." + format.fileExtension)
        try makeHostileArchive(archive, format: format)
        let destination = scratch.path("deep/inside/out")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        try ArchiveService.backend(backend).extract(
            archive, format: format, to: destination, entries: nil, password: nil, progress: .none
        )

        let everything = try snapshot(scratch.url).keys.filter { !$0.hasSuffix("/") }
        let outside = everything.filter { !$0.hasPrefix("deep/inside/out/") && $0 != archive.lastPathComponent }
        #expect(outside.isEmpty, "wrote outside: \(outside)")
        let inside = try snapshot(destination).keys.filter { !$0.hasSuffix("/") }
        #expect(inside.contains("fine.txt"))
        #expect(inside.contains("escaped.txt"))
    }
}

@Suite struct CancellationTests {
    @Test(arguments: [ArchiveFormat.sevenZip, .tarXz, .rar])
    func cancellingCreateLeavesNothing(format: ArchiveFormat) async throws {
        let scratch = try Scratch()
        let big = try scratch.makeFile("big.bin", size: 8_000_000)
        let archive = scratch.path("cancelled." + format.fileExtension)
        let service = ArchiveService(settings: RoutingSettings(rarsEnabled: true))
        await #expect(throws: ArchiveError.cancelled) {
            _ = try await service.create(
                PackRequest(destination: archive, sources: [big], format: format),
                progress: ArchiveProgress { done, _ in done == 0 }
            )
        }
        #expect(!FileManager.default.fileExists(atPath: archive.path))
    }
}
