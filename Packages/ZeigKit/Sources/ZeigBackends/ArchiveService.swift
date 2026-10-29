import Foundation
import ZeigCore

/// The one entry point the features use: picks the backend with `BackendRouter`, falls
/// back to the other one when a file won't open, runs the blocking work off the main
/// actor, and checks what the experimental backend writes.
public struct ArchiveService: Sendable {
    public var router: BackendRouter

    public init(settings: RoutingSettings = RoutingSettings()) {
        router = BackendRouter(settings: settings)
    }

    public init(router: BackendRouter) {
        self.router = router
    }

    public static func backend(_ id: BackendID) -> any ArchiveBackend {
        switch id {
        case .sevenZip: SevenZipBackend()
        case .libArchive: LibArchiveBackend()
        case .rars: RarsBackend()
        }
    }

    // MARK: Opening

    /// Lists the archive at `url`, detecting its format from its name and contents.
    public func open(_ url: URL, password: String? = nil) async throws(ArchiveError) -> ArchiveListing {
        let format = FormatDetector.detect(url)
        let router = router
        return try await background { () throws(ArchiveError) in
            let first = router.opener(for: format)
            ZeigLog.info("router", "open \(url.lastPathComponent): detected \(format?.displayName ?? "unknown format") → \(first.displayName)")
            do throws(ArchiveError) {
                let contents = try ZeigLog.measure(first.displayName, "list \(url.lastPathComponent)") { () throws(ArchiveError) in
                    try Self.backend(first).list(url, format: format, password: password)
                }
                return ArchiveListing(url: url, format: format, backend: first, entries: contents.entries, info: contents.info)
            } catch where error.allowsFallback {
                guard let second = router.fallback(for: format) else { throw error }
                ZeigLog.warning("router", "\(first.displayName) couldn't open \(url.lastPathComponent) (\(error)); trying \(second.displayName)")
                // The second backend detects the format itself: the name may have misled us.
                guard let contents = try? Self.backend(second).list(url, format: nil, password: password) else {
                    ZeigLog.error("router", "\(second.displayName) couldn't open it either")
                    throw error
                }
                return ArchiveListing(
                    url: url, format: format, backend: second, entries: contents.entries, info: contents.info, usedFallback: true
                )
            }
        }
    }

    /// Extracts `entries` (all if `nil`) of an opened archive into `destination`, which is
    /// created if needed. Uses the backend that opened it.
    public func extract(
        _ listing: ArchiveListing, entries: [ArchiveEntry]? = nil, to destination: URL,
        password: String? = nil, progress: ArchiveProgress = .none
    ) async throws(ArchiveError) {
        let format = listing.usedFallback ? nil : listing.format
        try await background { () throws(ArchiveError) in
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            } catch {
                throw .io(detail: "can't create \(destination.lastPathComponent)")
            }
            let what = "extract \(entries.map { "\($0.count) entries" } ?? "everything") of \(listing.url.lastPathComponent)"
            try ZeigLog.measure(listing.backend.displayName, what) { () throws(ArchiveError) in
                try Self.backend(listing.backend).extract(
                    listing.url, format: format, to: destination, entries: entries,
                    password: password, progress: progress
                )
            }
        }
    }

    /// Extracts everything into a new folder next to the archive ("photos.zip" → "photos",
    /// or "photos 2" if that exists). Returns the folder.
    public func extractToNewFolder(
        _ listing: ArchiveListing, entries: [ArchiveEntry]? = nil, password: String? = nil,
        progress: ArchiveProgress = .none
    ) async throws(ArchiveError) -> URL {
        let folder = FileNaming.unique(FileNaming.extractionFolder(for: listing.url))
        do throws(ArchiveError) {
            try await extract(listing, entries: entries, to: folder, password: password, progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return folder
    }

    /// Decompresses everything and checks it.
    public func test(_ listing: ArchiveListing, password: String? = nil, progress: ArchiveProgress = .none) async throws(ArchiveError) {
        let format = listing.usedFallback ? nil : listing.format
        try await background { () throws(ArchiveError) in
            try ZeigLog.measure(listing.backend.displayName, "test \(listing.url.lastPathComponent)") { () throws(ArchiveError) in
                try Self.backend(listing.backend).test(listing.url, format: format, password: password, progress: progress)
            }
        }
    }

    // MARK: Creating

    public struct PackResult: Sendable {
        /// The archive, or all volumes of a split archive.
        public var files: [URL]
        public var backend: BackendID
        public var verification: Verification
    }

    /// The independent check of an archive the experimental backend wrote.
    public enum Verification: Sendable, Equatable {
        /// Archives from 7-Zip and libarchive aren't re-read.
        case notNeeded
        /// 7-Zip opened and tested the archive without errors and sees the same file names.
        case passed
        /// 7-Zip couldn't read it back. The files are kept so the user can decide.
        case failed(ArchiveError)
    }

    public func create(_ request: PackRequest, progress: ArchiveProgress = .none) async throws(ArchiveError) -> PackResult {
        guard let id = router.creator(for: request.format) else { throw .readOnlyFormat }
        return try await background { () throws(ArchiveError) in
            ZeigLog.info("router", "create \(request.format.displayName) → \(id.displayName)")
            let files = try ZeigLog.measure(id.displayName, "create \(request.destination.lastPathComponent)") { () throws(ArchiveError) in
                try Self.backend(id).create(request, progress: progress)
            }
            guard id == .rars, let first = files.first else {
                return PackResult(files: files, backend: id, verification: .notNeeded)
            }
            do throws(ArchiveError) {
                try Self.verifyWithSevenZip(first, request: request)
                ZeigLog.info("router", "7-Zip check of the rars archive passed")
                return PackResult(files: files, backend: id, verification: .passed)
            } catch {
                ZeigLog.warning("router", "7-Zip check of the rars archive failed: \(error.detail ?? error.message)")
                return PackResult(files: files, backend: id, verification: .failed(error))
            }
        }
    }
}

extension ArchiveService {
    /// Has 7-Zip, an independent RAR reader, decompress the whole archive and list the same
    /// names that went in. Catches data errors and names other tools would show garbled
    /// (rars writes RAR 2.9 names as raw bytes, which other readers take as a legacy code page).
    static func verifyWithSevenZip(_ archive: URL, request: PackRequest) throws(ArchiveError) {
        let sevenZip = SevenZipBackend()
        let password = request.effectivePassword
        try sevenZip.test(archive, format: .rar, password: password, progress: .none)
        let read = Set(try sevenZip.list(archive, format: .rar, password: password).entries
            .filter { !$0.isDirectory }
            .map { $0.path.precomposedStringWithCanonicalMapping })
        let written = Set(try SourceWalker.items(for: request.sources)
            .filter { !$0.isDirectory }
            .map { $0.nameInArchive.precomposedStringWithCanonicalMapping })
        let unreadable = written.subtracting(read)
        guard unreadable.isEmpty else {
            throw .corrupt(detail: "7-Zip reads \(unreadable.count) file name(s) differently, such as \"\(unreadable.sorted()[0])\"")
        }
    }
}

/// Runs blocking backend work on a background thread and hands back its typed result.
func background<T: Sendable>(_ work: @escaping @Sendable () throws(ArchiveError) -> T) async throws(ArchiveError) -> T {
    let result: Result<T, ArchiveError> = await Task.detached(priority: .userInitiated) {
        do throws(ArchiveError) {
            return .success(try work())
        } catch {
            return .failure(error)
        }
    }.value
    return try result.get()
}
