import Testing
import ZeigCore

@Suite struct ArchiveTreeTests {
    let entries = [
        ArchiveEntry(index: 0, path: "docs/a.txt", size: 10),
        ArchiveEntry(index: 1, path: "docs/deep/b.txt", size: 20),
        ArchiveEntry(index: 2, path: "readme.md", size: 5),
        ArchiveEntry(index: 3, path: "empty/", size: 0, isDirectory: true),
        ArchiveEntry(index: 4, path: "../../evil.txt", size: 1),
    ]

    @Test func implicitFoldersAppear() {
        let tree = ArchiveTree(entries: entries)
        let top = tree.children(of: "")
        #expect(top.map(\.name) == ["docs", "empty", "evil.txt", "readme.md"], "folders first, then files")
        #expect(tree.children(of: "docs").map(\.name) == ["deep", "a.txt"])
    }

    @Test func folderSizesAddUp() {
        let tree = ArchiveTree(entries: entries)
        let docs = tree.children(of: "").first { $0.name == "docs" }
        #expect(docs?.size == 30)
        #expect(docs?.entry == nil, "docs/ isn't stored, only implied")
        #expect(tree.children(of: "").first { $0.name == "empty" }?.entry?.index == 3)
    }

    @Test func extractingAFolderTakesEverythingInside() {
        let tree = ArchiveTree(entries: entries)
        let docs = tree.children(of: "").first { $0.name == "docs" }!
        #expect(Set(tree.entries(for: docs).map(\.index)) == [0, 1])
        let file = tree.children(of: "").first { $0.name == "readme.md" }!
        #expect(tree.entries(for: file).map(\.index) == [2])
    }

    @Test func hostilePathsShowWhereTheyWillLand() {
        let tree = ArchiveTree(entries: entries)
        #expect(tree.children(of: "").contains { $0.path == "evil.txt" })
    }
}
