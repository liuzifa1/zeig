import Foundation
import Testing
@testable import ZeigBackends
import ZeigCore

/// A scratch folder per test, removed afterwards.
final class Scratch {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("zeig-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func path(_ relative: String) -> URL { url.appendingPathComponent(relative) }

    /// A folder with the awkward cases: nesting, a non-ASCII name, an empty file, an empty
    /// folder, and a file big enough to need several compression blocks.
    func makeTree(named name: String = "tree") throws -> URL {
        let root = path(name)
        let files: [String: Data] = [
            "hello.txt": Data("hello world\n".utf8),
            "sub/nested.txt": Data(String(repeating: "nested line\n", count: 500).utf8),
            "sub/deeper/binary.bin": randomData(300_000),
            "naïve résumé ✓.txt": Data("unicode\n".utf8),
            "empty.txt": Data(),
        ]
        for (relative, data) in files {
            let file = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("empty folder"), withIntermediateDirectories: true)
        return root
    }

    func makeFile(_ name: String, size: Int = 50_000) throws -> URL {
        let file = path(name)
        try randomData(size).write(to: file)
        return file
    }
}

/// Deterministic pseudo-random bytes (compressible enough to be realistic, not uniform).
func randomData(_ count: Int) -> Data {
    var generator = SplitMix(seed: UInt64(count))
    return Data((0..<count).map { _ in UInt8(truncatingIfNeeded: generator.next() % 64) })
}

struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Relative path → contents for every regular file under `root`; folders as "path/".
func snapshot(_ root: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    let base = root.resolvingSymlinksInPath().path
    let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])
    while let url = enumerator?.nextObject() as? URL {
        let relative = String(url.resolvingSymlinksInPath().path.dropFirst(base.count + 1))
        if (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
            result[relative + "/"] = Data()
        } else {
            result[relative] = try Data(contentsOf: url)
        }
    }
    return result
}

/// Compares file names after Unicode normalization: some formats store NFD, some NFC.
func normalized(_ snapshot: [String: Data]) -> [String: Data] {
    Dictionary(uniqueKeysWithValues: snapshot.map { ($0.key.precomposedStringWithCanonicalMapping, $0.value) })
}

/// `snapshot` without folder markers (for formats that don't store empty folders).
func filesOnly(_ snapshot: [String: Data]) -> [String: Data] {
    snapshot.filter { !$0.key.hasSuffix("/") }
}

/// What differs between two snapshots, for test failure messages.
func differences(_ actual: [String: Data], _ expected: [String: Data]) -> String {
    var lines: [String] = []
    for key in Set(actual.keys).union(expected.keys).sorted() {
        switch (actual[key], expected[key]) {
        case (nil, _?): lines.append("missing \(key)")
        case (_?, nil): lines.append("unexpected \(key)")
        case let (a?, e?) where a != e: lines.append("\(key): \(a.count) bytes, expected \(e.count)")
        default: break
        }
    }
    return lines.joined(separator: "; ")
}
