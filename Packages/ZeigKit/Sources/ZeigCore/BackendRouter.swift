import Foundation

/// What each backend can read and write, as Zeig uses it.
///
/// These tables are the input to `BackendRouter`. They describe Zeig's integration, not
/// everything the libraries could do: 7-Zip can read a .tar.gz as a gzip with a tar inside,
/// but the bridge opens one layer only, so compressed tars count as unreadable by 7-Zip.
/// `CapabilityTests` checks the 7-Zip and libarchive tables against the real libraries.
public struct BackendCapabilities: Sendable {
    public var reads: Set<ArchiveFormat>
    public var writes: Set<ArchiveFormat>

    public init(reads: Set<ArchiveFormat>, writes: Set<ArchiveFormat>) {
        self.reads = reads.union(writes)
        self.writes = writes
    }

    public static let sevenZip = BackendCapabilities(
        reads: [
            .rar, .iso, .cpio, .xar, .ar, .deb, .cab, .dmg, .lzh, .arj, .chm, .rpm, .msi,
            .squashfs, .vhd, .vmdk, .zstd, .lzma, .compress,
        ],
        writes: [.zip, .sevenZip, .tar, .gzip, .bzip2, .xz, .wim]
    )

    public static let libArchive = BackendCapabilities(
        // ar could be written too, but libarchive's ar writer takes no folders, so Zeig
        // doesn't offer it.
        reads: [.rar, .cab, .lzh, .deb, .ar],
        writes: [
            .zip, .sevenZip, .tar, .tarGzip, .tarBzip2, .tarXz, .tarZstd, .tarLz4,
            .gzip, .bzip2, .xz, .zstd, .lz4, .lzip, .lzma, .compress,
            .iso, .cpio, .xar,
        ]
    )

    public static let rars = BackendCapabilities(reads: [.rar], writes: [.rar])
}

/// The user's choices that change routing (Settings → Experimental).
public struct RoutingSettings: Sendable, Equatable {
    /// "Test RAR backend": rars creates RAR archives. Off means RAR can't be created.
    public var rarsEnabled: Bool
    /// "Use test RAR backend for opening RAR too". Only applies when `rarsEnabled`.
    public var rarsOpensRar: Bool

    public init(rarsEnabled: Bool = false, rarsOpensRar: Bool = false) {
        self.rarsEnabled = rarsEnabled
        self.rarsOpensRar = rarsOpensRar
    }
}

/// Picks the backend for a format. The rule, in order:
///
/// 1. RAR: rars when the experimental backend is on (opening only if its second switch is on
///    too), otherwise 7-Zip opens it and nothing creates it.
/// 2. 7-Zip reads and writes the format → 7-Zip, for both.
/// 3. 7-Zip lacks the format, or only reads it while libarchive reads *and* writes it →
///    libarchive, for both.
/// 4. Both only read it → 7-Zip.
///
/// `fallback` is who to try when the first choice fails to open a file.
public struct BackendRouter: Sendable {
    public var settings: RoutingSettings
    public var sevenZip: BackendCapabilities
    public var libArchive: BackendCapabilities
    public var rars: BackendCapabilities

    public init(
        settings: RoutingSettings = RoutingSettings(),
        sevenZip: BackendCapabilities = .sevenZip,
        libArchive: BackendCapabilities = .libArchive,
        rars: BackendCapabilities = .rars
    ) {
        self.settings = settings
        self.sevenZip = sevenZip
        self.libArchive = libArchive
        self.rars = rars
    }

    /// Who creates `format`, or `nil` if no enabled backend can.
    public func creator(for format: ArchiveFormat) -> BackendID? {
        if format == .rar {
            return settings.rarsEnabled && rars.writes.contains(.rar) ? .rars : nil
        }
        if sevenZip.writes.contains(format) { return .sevenZip }
        if libArchive.writes.contains(format) { return .libArchive }
        return nil
    }

    /// Who opens `format` (lists, extracts, tests). A `nil` format (not one Zeig names) goes
    /// to 7-Zip, which detects formats by content.
    public func opener(for format: ArchiveFormat?) -> BackendID {
        guard let format else { return .sevenZip }
        if format == .rar, settings.rarsEnabled, settings.rarsOpensRar { return .rars }
        if sevenZip.writes.contains(format) { return .sevenZip }
        if libArchive.writes.contains(format), libArchive.reads.contains(format) { return .libArchive }
        if sevenZip.reads.contains(format) { return .sevenZip }
        if libArchive.reads.contains(format) { return .libArchive }
        return .sevenZip
    }

    /// The backend to try when `opener(for:)` fails with an error that allows fallback.
    public func fallback(for format: ArchiveFormat?) -> BackendID? {
        switch opener(for: format) {
        case .sevenZip: .libArchive
        case .libArchive: .sevenZip
        // If rars can't open a RAR, 7-Zip (the normal RAR reader) gets a go.
        case .rars: .sevenZip
        }
    }

    /// Formats that can be created right now, common ones first.
    public var creatableFormats: [ArchiveFormat] {
        let all = ArchiveFormat.allCases.filter { creator(for: $0) != nil }
        return ArchiveFormat.common.filter(all.contains) + all.filter { !ArchiveFormat.common.contains($0) }
    }
}
