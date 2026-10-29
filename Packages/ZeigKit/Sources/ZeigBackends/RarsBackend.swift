import Foundation
import ZeigCore
import ZeigRars

/// rars, an independent RAR implementation in Rust, through UniFFI (`ZeigRars`, generated
/// from Native/rars-ffi).
///
/// **Experimental.** Used only when the user turns it on in Settings, and `ArchiveService`
/// has 7-Zip test every archive it creates. See GuideTopic "rar-experimental" for what the
/// user is told.
public struct RarsBackend: ArchiveBackend {
    public let id = BackendID.rars

    public init() {}

    public var version: String { rarsVersion() }

    public func list(_ archive: URL, format: ArchiveFormat?, password: String?) throws(ArchiveError) -> ArchiveContents {
        let entries = try call { try listEntries(path: archive.path, password: password) }
        ZeigLog.debug("rars", "\(archive.lastPathComponent): \(entries.count) entries")
        return ArchiveContents(entries: entries.enumerated().map { index, entry in
            ArchiveEntry(
                index: index,
                path: entry.path,
                size: entry.size,
                packedSize: entry.packedSize,
                modified: entry.modified.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                isDirectory: entry.isDirectory,
                isEncrypted: entry.isEncrypted
            )
        }, info: ArchiveInfo(formatName: "RAR"))
    }

    public func extract(
        _ archive: URL, format: ArchiveFormat?, to destination: URL, entries: [ArchiveEntry]?,
        password: String?, progress: ArchiveProgress
    ) throws(ArchiveError) {
        let relay = ProgressRelay(progress)
        guard let entries else {
            try call { try extractArchive(path: archive.path, destination: destination.path, password: password, progress: relay) }
            return
        }
        // rars extracts everything or nothing: extract to a scratch folder next to the
        // destination (same volume, so moves are cheap), then move the chosen entries over.
        let scratch = destination.appendingPathComponent(".zeig-rars-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        } catch {
            throw .io(detail: "can't create a temporary folder")
        }
        defer { try? FileManager.default.removeItem(at: scratch) }
        try call { try extractArchive(path: archive.path, destination: scratch.path, password: password, progress: relay) }
        for entry in entries where !entry.isDirectory {
            guard let relative = entry.sanitizedPath else { continue }
            let source = scratch.appendingPathComponent(relative)
            let target = destination.appendingPathComponent(relative)
            do {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: source, to: target)
            } catch {
                throw .io(detail: "can't move \(entry.name) into place")
            }
        }
    }

    public func test(_ archive: URL, format: ArchiveFormat?, password: String?, progress: ArchiveProgress) throws(ArchiveError) {
        try call { try testArchive(path: archive.path, password: password) }
    }

    public func create(_ request: PackRequest, progress: ArchiveProgress) throws(ArchiveError) -> [URL] {
        guard request.format == .rar else { throw .readOnlyFormat }
        let options = Self.options(for: request)
        ZeigLog.info("rars", "create \(request.destination.lastPathComponent): \(options.version), level \(options.level.map(String.init) ?? "default"), solid \(options.solid), recovery \(options.recoveryPercent.map { "\($0)%" } ?? "none"), volumes \(options.volumeSize.map(String.init) ?? "none")")
        let written = try call {
            try createArchive(
                destination: request.destination.path,
                sources: request.sources.map(\.path),
                options: options,
                progress: ProgressRelay(progress)
            )
        }
        return written.map { URL(fileURLWithPath: $0) }
    }

    /// The rars options for a request. Exposed for tests.
    static func options(for request: PackRequest) -> RarPackOptions {
        let version: RarVersion = switch request.value(FormatOptions.rarVersion.id) {
        case "rar5": .rar50
        case "rar29": .rar29
        default: .rar70
        }
        let password = request.effectivePassword
        let recovery = UInt64(request.value(FormatOptions.recoveryRecord.id)) ?? 0
        // rars only splits RAR 5/7 archives.
        let volumeSize = version == .rar29 ? nil : FormatOptions.byteCount(request.value(FormatOptions.volumeSize.id))
        return RarPackOptions(
            version: version,
            level: UInt8(request.level.level(in: 0...5)),
            solid: request.isOn(FormatOptions.rarSolid.id),
            password: password,
            encryptHeaders: password != nil && request.isOn(FormatOptions.encryptNames.id),
            recoveryPercent: recovery > 0 ? recovery : nil,
            volumeSize: volumeSize,
            comment: nil
        )
    }
}

/// Swift side of rars' `RarProgress` callback interface.
private final class ProgressRelay: RarProgress {
    let reporter: ArchiveProgress
    init(_ reporter: ArchiveProgress) { self.reporter = reporter }

    func report(completed: UInt64, total: UInt64) -> Bool {
        reporter.report(completed, total)
    }
}

/// Runs a rars call, mapping its errors (and a Rust panic, which UniFFI reports as an
/// unexpected error) to `ArchiveError`.
private func call<T>(_ body: () throws -> T) throws(ArchiveError) -> T {
    do {
        return try body()
    } catch let error as RarError {
        ZeigLog.error("rars", "\(error)")
        throw switch error {
        case .PasswordRequired: .passwordRequired
        case .WrongPassword: .wrongPassword
        case .Corrupt(let message): .corrupt(detail: message)
        case .Unsupported(let message): .unsupportedMethod(detail: message)
        case .Io(let message): .io(detail: message)
        case .Cancelled: .cancelled
        case .InvalidOption(let message): .invalidOptions(detail: message)
        case .Other(let message): .other(detail: message)
        }
    } catch {
        throw .other(detail: "rars: \(error)")
    }
}
