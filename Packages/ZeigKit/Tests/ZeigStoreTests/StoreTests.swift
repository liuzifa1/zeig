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

    @Test func commonFolderIsTheSharedParentOrTheTop() throws {
        let library = FileLibrary(root: root)
        let work = root.appendingPathComponent("Work")
        let a = work.appendingPathComponent("a.txt"), b = work.appendingPathComponent("b.txt")
        let c = root.appendingPathComponent("Other/c.txt")
        #expect(library.commonFolder(of: [a, b]).path == work.standardizedFileURL.path)
        #expect(library.commonFolder(of: [a, c]) == root, "a selection in Recent can span folders")
        #expect(library.commonFolder(of: []) == root)
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

    @Test func movingAFolderCarriesWhatsInsideIt() {
        let store = RecentStore(fileURL: nil)
        store.record("Trips/rome.zip", .opened)
        store.record("Trips/2026/paris.7z", .opened)
        store.record("Tripsheet.zip", .opened)
        store.move("Trips", to: "Holidays")
        #expect(Set(store.entries.map(\.relativePath)) == ["Holidays/rome.zip", "Holidays/2026/paris.7z", "Tripsheet.zip"],
                "only paths inside the folder move, not names that merely start the same")
        store.remove("Holidays")
        #expect(store.entries.map(\.relativePath) == ["Tripsheet.zip"])
    }

    @Test func persists() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("recent-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        RecentStore(fileURL: file).record("x.7z", .created)
        #expect(RecentStore(fileURL: file).entries.map(\.relativePath) == ["x.7z"])
    }

    @Test func dayGroups() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 12))!
        let hour: TimeInterval = 3600
        #expect(RecentDay.title(for: now - hour, now: now, calendar: calendar) == "Today")
        #expect(RecentDay.title(for: now - 13 * hour, now: now, calendar: calendar) == "Yesterday")
        #expect(RecentDay.title(for: now - 3 * 24 * hour, now: now, calendar: calendar) == "This Week")
        #expect(RecentDay.title(for: now - 9 * 24 * hour, now: now, calendar: calendar) == "Earlier")
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

@Suite struct StorageReportTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeig-storage-\(UUID().uuidString)")

    private func write(_ path: String, bytes: Int) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
    }

    @Test func sortsBytesByKindAndFindsExtractedArchives() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("photos.zip", bytes: 100)
        try write("photos/a.jpg", bytes: 300)
        try write("photos/inner.7z", bytes: 50)    // inside an extracted folder: counts as extracted
        try write("Work/report.tar.gz", bytes: 40)
        try write("Work/report 2/r.txt", bytes: 7) // numbered extraction folder
        try write("Work/report 2b/x.txt", bytes: 1) // not an extraction name
        try write("photos 3/b.jpg", bytes: 3)      // extracted again: same archive, second folder
        try write("notes.txt", bytes: 10)
        try write(".hidden", bytes: 1000)          // skipped, as in the lists

        let report = StorageReport.scan(root)
        #expect(report.total == 511)
        #expect(report.size(of: .archives) == 140)
        #expect(report.size(of: .extracted) == 360)
        #expect(report.size(of: .other) == 11)
        #expect(StorageReport.Kind.allCases.reduce(UInt64(0)) { $0 + report.size(of: $1) } == report.total)

        #expect(report.extracted.map(\.archive.relativePath) == ["photos.zip", "Work/report.tar.gz"])
        #expect(report.extracted.map { $0.folders.map(\.relativePath) } == [["photos", "photos 3"], ["Work/report 2"]])
        #expect(report.extracted.first?.foldersSize == 353)

        #expect(report.largestFiles.first?.relativePath == "photos/a.jpg")
        #expect(report.largestFiles.count == 8)
        #expect(StorageReport.scan(root, largestLimit: 2).largestFiles.map(\.size) == [300, 100])
    }

    @Test func extractionNames() {
        #expect(StorageReport.isExtractionName("Photos", stem: "photos"))
        #expect(StorageReport.isExtractionName("photos 12", stem: "photos"))
        #expect(!StorageReport.isExtractionName("photos ", stem: "photos"))
        #expect(!StorageReport.isExtractionName("photos2", stem: "photos"))
        #expect(!StorageReport.isExtractionName("photos old", stem: "photos"))
    }
}
