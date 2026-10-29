import Foundation
import Testing
import ZeigCore
@testable import ZeigStore

@MainActor
@Suite struct FileLibraryTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeig-library-\(UUID().uuidString)")

    @Test func importCopiesAndAvoidsNameClashes() throws {
        let library = FileLibrary(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).zip")
        try Data("zip".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        let first = try library.importFiles([outside])
        let second = try library.importFiles([outside])
        #expect(first[0].deletingLastPathComponent().standardizedFileURL.path == library.root.path)
        #expect(second[0].lastPathComponent.hasSuffix(" 2.zip"))
        #expect(FileManager.default.fileExists(atPath: outside.path), "the original stays where it was")
        #expect(library.contents().count == 2)
        #expect(library.contents().allSatisfy { $0.format == .zip && $0.isArchive })
    }

    @Test func foldersSortFirst() throws {
        let library = FileLibrary(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("a.txt"))
        try library.createFolder(named: "z folder")
        #expect(library.contents().map(\.name) == ["z folder", "a.txt"])
    }

    @Test func renameAndDelete() throws {
        let library = FileLibrary(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try library.createFolder(named: "Docs")
        let renamed = try library.rename(folder, to: "../Escape/Attempt")
        #expect(renamed.deletingLastPathComponent().standardizedFileURL.path == library.root.path, "no path tricks in names")
        #expect(renamed.lastPathComponent == "-Escape-Attempt")
        try library.delete([renamed])
        #expect(library.contents().isEmpty)
    }

    @Test func relativePaths() throws {
        let library = FileLibrary(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try library.createFolder(named: "Trips")
        let file = folder.appendingPathComponent("rome.zip")
        try Data().write(to: file)
        #expect(library.relativePath(of: file) == "Trips/rome.zip")
        #expect(library.item(atRelativePath: "Trips/rome.zip")?.format == .zip)
        #expect(library.allItems().map(\.relativePath).sorted() == ["Trips", "Trips/rome.zip"])
    }

    @Test func openedFilesLeaveTheInbox() throws {
        let library = FileLibrary(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let sent = inbox.appendingPathComponent("from-mail.zip")
        try Data("zip".utf8).write(to: sent)

        let adopted = try library.adoptOpenedFile(sent)
        #expect(adopted.lastPathComponent == "from-mail.zip")
        #expect(adopted.deletingLastPathComponent().standardizedFileURL.path == library.root.path)
        #expect(!FileManager.default.fileExists(atPath: inbox.path), "the empty Inbox is removed")
    }

    @Test func duplicateNamesLikeFiles() throws {
        let library = FileLibrary(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("backup.tar.gz")
        try Data("x".utf8).write(to: file)
        let first = try library.duplicate([file])
        let second = try library.duplicate([file])
        #expect(first.map(\.lastPathComponent) == ["backup copy.tar.gz"])
        #expect(second.map(\.lastPathComponent) == ["backup copy 2.tar.gz"])
    }

    @Test func newFolderWithItems() throws {
        let library = FileLibrary(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.txt")
        let b = root.appendingPathComponent("b.txt")
        try Data().write(to: a)
        try Data().write(to: b)
        let folder = try library.newFolder(containing: [a, b])
        #expect(folder.lastPathComponent == "New Folder")
        #expect(library.contents(of: folder).map(\.name) == ["a.txt", "b.txt"])
        #expect(library.contents().map(\.name) == ["New Folder"])
    }

    @Test func moveIgnoresImpossibleMoves() throws {
        let library = FileLibrary(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let outer = try library.createFolder(named: "Outer")
        let inner = try library.createFolder(named: "Inner", in: outer)
        try library.move([outer], into: inner)
        try library.move([inner], into: outer)
        #expect(library.allFolders().map(\.relativePath) == ["Outer", "Outer/Inner"])
    }

    @Test func changesAreCounted() throws {
        let library = FileLibrary(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = library.changeCount
        try library.createFolder(named: "x")
        #expect(library.changeCount == before + 1)
    }
}

@MainActor
@Suite struct RecentStoreTests {
    @Test func newestFirstOncePerFile() {
        let store = RecentStore(fileURL: nil)
        store.record("a.zip", .opened, at: Date(timeIntervalSince1970: 1))
        store.record("b.zip", .created, at: Date(timeIntervalSince1970: 2))
        store.record("a.zip", .extracted, at: Date(timeIntervalSince1970: 3))
        #expect(store.entries.map(\.relativePath) == ["a.zip", "b.zip"])
        #expect(store.entries[0].action == .extracted)
    }

    @Test func limitDropsTheOldest() {
        let store = RecentStore(fileURL: nil, limit: 2)
        store.record("1", .opened)
        store.record("2", .opened)
        store.record("3", .opened)
        #expect(store.entries.map(\.relativePath) == ["3", "2"])
    }

    @Test func pruneAndMove() {
        let store = RecentStore(fileURL: nil)
        store.record("gone.zip", .opened)
        store.record("kept.zip", .opened)
        store.prune { $0 == "kept.zip" }
        store.move("kept.zip", to: "Folder/kept.zip")
        #expect(store.entries.map(\.relativePath) == ["Folder/kept.zip"])
    }

    @Test func persists() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("recent-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        RecentStore(fileURL: file).record("x.7z", .created)
        #expect(RecentStore(fileURL: file).entries.map(\.relativePath) == ["x.7z"])
    }
}

@MainActor
@Suite struct AppSettingsTests {
    @Test func defaultsAndPersistence() throws {
        let suite = "zeig-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(!settings.rarsEnabled, "the experimental backend starts off")
        #expect(settings.defaultFormat == .zip)
        #expect(settings.routing == RoutingSettings())

        settings.rarsEnabled = true
        settings.defaultLevel = .maximum
        settings.remember(["7z.method": "PPMd"], for: .sevenZip)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.rarsEnabled)
        #expect(reloaded.defaultLevel == .maximum)
        #expect(reloaded.advanced(for: .sevenZip) == ["7z.method": "PPMd"])
    }
}
