import Testing
import ZeigCore

/// The routing rule from the README, format by format.
@Suite struct BackendRouterTests {
    let router = BackendRouter()

    @Test("7-Zip reads and writes → 7-Zip for both", arguments: [
        ArchiveFormat.zip, .sevenZip, .tar, .gzip, .bzip2, .xz, .wim,
    ])
    func sevenZipOwnsWhatItWrites(format: ArchiveFormat) {
        #expect(router.creator(for: format) == .sevenZip)
        #expect(router.opener(for: format) == .sevenZip)
    }

    @Test("7-Zip lacks it, or only reads what libarchive writes → libarchive for both", arguments: [
        ArchiveFormat.tarGzip, .tarBzip2, .tarXz, .tarZstd, .tarLz4,
        .zstd, .lz4, .lzip, .lzma, .compress, .iso, .cpio, .xar,
    ])
    func libArchiveOwnsTheRest(format: ArchiveFormat) {
        #expect(router.creator(for: format) == .libArchive)
        #expect(router.opener(for: format) == .libArchive)
    }

    @Test("Both only read → 7-Zip opens, nobody creates", arguments: [
        ArchiveFormat.cab, .lzh, .deb, .ar,
    ])
    func readOnlyInBothGoesToSevenZip(format: ArchiveFormat) {
        #expect(router.opener(for: format) == .sevenZip)
        #expect(router.creator(for: format) == nil)
    }

    @Test func unknownFormatsGoToSevenZipDetection() {
        #expect(router.opener(for: nil) == .sevenZip)
        #expect(router.fallback(for: nil) == .libArchive)
    }

    @Test func rarWithTheTestBackendOff() {
        #expect(router.creator(for: .rar) == nil)
        #expect(router.opener(for: .rar) == .sevenZip)
        #expect(!router.creatableFormats.contains(.rar))
    }

    @Test func rarWithTheTestBackendOn() {
        let router = BackendRouter(settings: RoutingSettings(rarsEnabled: true))
        #expect(router.creator(for: .rar) == .rars)
        #expect(router.opener(for: .rar) == .sevenZip, "opening stays with 7-Zip until the second switch")
        #expect(router.creatableFormats.contains(.rar))
    }

    @Test func rarWithBothSwitchesOn() {
        let router = BackendRouter(settings: RoutingSettings(rarsEnabled: true, rarsOpensRar: true))
        #expect(router.opener(for: .rar) == .rars)
        #expect(router.fallback(for: .rar) == .sevenZip)
    }

    @Test func secondSwitchAloneDoesNothing() {
        let router = BackendRouter(settings: RoutingSettings(rarsEnabled: false, rarsOpensRar: true))
        #expect(router.opener(for: .rar) == .sevenZip)
    }

    @Test func commonFormatsComeFirst() {
        #expect(Array(router.creatableFormats.prefix(4)) == ArchiveFormat.common)
    }
}
