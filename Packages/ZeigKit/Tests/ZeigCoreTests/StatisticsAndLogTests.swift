import Foundation
import Testing
import ZeigCore

@Suite struct ArchiveStatisticsTests {
    @Test func countsFilesFoldersAndImpliedFolders() {
        let entries = [
            ArchiveEntry(index: 0, path: "a/b/c.txt", size: 100, isEncrypted: true),
            ArchiveEntry(index: 1, path: "a/d.txt", size: 300),
            ArchiveEntry(index: 2, path: "empty/", size: 0, isDirectory: true),
        ]
        let stats = ArchiveStatistics(entries: entries, archiveSize: 100)
        #expect(stats.fileCount == 2)
        #expect(stats.folderCount == 3, "a, a/b (implied) and empty (stored)")
        #expect(stats.encryptedCount == 1)
        #expect(stats.originalSize == 400)
        #expect(stats.ratio == 0.25)
        #expect(stats.savings == 0.75)
    }

    @Test func emptyArchivesHaveNoRatio() {
        #expect(ArchiveStatistics(entries: [], archiveSize: 22).ratio == nil)
    }
}

@Suite(.serialized) struct ZeigLogTests {
    @Test func keepsTheNewestLinesUpToCapacity() {
        ZeigLog.clear()
        for i in 0..<(ZeigLog.capacity + 10) { ZeigLog.debug("test", "line \(i)") }
        let lines = ZeigLog.snapshot()
        #expect(lines.count == ZeigLog.capacity)
        #expect(lines.last?.message == "line \(ZeigLog.capacity + 9)")
        #expect(lines.first?.message == "line 10")
        ZeigLog.clear()
    }

    @Test func measureLogsSuccessAndFailure() {
        ZeigLog.clear()
        struct Boom: Error {}
        _ = ZeigLog.measure("test", "fast thing") { 42 }
        #expect(throws: Boom.self) { try ZeigLog.measure("test", "failing thing") { () throws(Boom) in throw Boom() } }
        let lines = ZeigLog.snapshot()
        #expect(lines.contains { $0.level == .info && $0.message.hasPrefix("fast thing — ") })
        #expect(lines.contains { $0.level == .error && $0.message.hasPrefix("failing thing failed") })
        #expect(ZeigLog.export().contains("[test] fast thing"))
        ZeigLog.clear()
    }
}
