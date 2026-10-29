import CryptoKit
import Foundation
import Testing
@testable import ZeigBackends
import ZeigCore

/// Real RAR archives made by RARLAB's rar (Native/scripts/make-rar-fixtures.sh), opened by
/// both RAR readers. Skipped until the fixtures exist.
@Suite(.enabled(if: RarFixtures.manifest != nil, "Run Native/scripts/make-rar-fixtures.sh to create RAR fixtures"))
struct RarFixtureTests {
    @Test("7-Zip extracts every fixture exactly", arguments: RarFixtures.archives)
    func sevenZip(fixture: RarFixtures.Archive) throws {
        try check(fixture, with: .sevenZip)
    }

    @Test("rars extracts every fixture exactly", arguments: RarFixtures.archives)
    func rars(fixture: RarFixtures.Archive) throws {
        try check(fixture, with: .rars)
    }

    @Test("Both readers list the same files", arguments: RarFixtures.archives)
    func listingsAgree(fixture: RarFixtures.Archive) throws {
        let url = RarFixtures.url(fixture)
        func names(_ backend: BackendID) throws -> Set<String> {
            Set(try ArchiveService.backend(backend).list(url, format: .rar, password: fixture.password).entries
                .filter { !$0.isDirectory }
                .map { $0.path.precomposedStringWithCanonicalMapping })
        }
        #expect(try names(.sevenZip) == names(.rars))
        #expect(try names(.sevenZip) == Set(fixture.files.keys.map { $0.precomposedStringWithCanonicalMapping }))
    }

    @Test("Password fixtures refuse a wrong password", arguments: RarFixtures.archives.filter { $0.password != nil })
    func wrongPassword(fixture: RarFixtures.Archive) throws {
        let scratch = try Scratch()
        for backend in [BackendID.sevenZip, .rars] {
            #expect(throws: ArchiveError.self, "\(backend)") {
                try ArchiveService.backend(backend).extract(
                    RarFixtures.url(fixture), format: .rar, to: scratch.url, entries: nil, password: "wrong", progress: .none
                )
            }
        }
    }

    private func check(_ fixture: RarFixtures.Archive, with backend: BackendID) throws {
        let scratch = try Scratch()
        try ArchiveService.backend(backend).extract(
            RarFixtures.url(fixture), format: .rar, to: scratch.url, entries: nil,
            password: fixture.password, progress: .none
        )
        var hashes: [String: String] = [:]
        for (path, data) in try snapshot(scratch.url) where !path.hasSuffix("/") {
            hashes[path.precomposedStringWithCanonicalMapping] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        let expected = Dictionary(uniqueKeysWithValues: fixture.files.map { ($0.key.precomposedStringWithCanonicalMapping, $0.value) })
        #expect(hashes == expected, "\(backend): \(Set(hashes.keys).symmetricDifference(expected.keys).sorted())")
        for folder in fixture.emptyFolders {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: scratch.path(folder).path, isDirectory: &isDirectory) && isDirectory.boolValue,
                    "\(backend): empty folder \(folder)")
        }
    }
}

/// manifest.json written by make-rar-fixtures.sh.
enum RarFixtures {
    struct Manifest: Decodable { var archives: [Archive] }

    struct Archive: Decodable, Sendable, CustomTestStringConvertible {
        var file: String
        var password: String?
        /// Relative path → SHA-256 (hex) of the file's contents.
        var files: [String: String]
        var emptyFolders: [String]
        var testDescription: String { file }
    }

    static let directory = Bundle.module.resourceURL?.appendingPathComponent("Fixtures/RAR/archives")

    static let manifest: Manifest? = directory
        .flatMap { try? Data(contentsOf: $0.appendingPathComponent("manifest.json")) }
        .flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }

    static var archives: [Archive] { manifest?.archives ?? [] }

    static func url(_ archive: Archive) -> URL { directory!.appendingPathComponent(archive.file) }
}
