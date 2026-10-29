import Foundation
import os
import Synchronization

/// One line in the developer console.
public struct LogEntry: Sendable, Identifiable, Hashable {
    public enum Level: String, Sendable, CaseIterable {
        case debug, info, warning, error

        public var symbol: String {
            switch self {
            case .debug: "·"
            case .info: "›"
            case .warning: "!"
            case .error: "✕"
            }
        }
    }

    public let id: UInt64
    public let date: Date
    public let level: Level
    /// Who said it: "7-Zip", "libarchive", "rars", "router", "stderr", …
    public let source: String
    public let message: String
}

/// What the app and its engines report, for Settings → Developer → Console.
///
/// Every component writes here (`ZeigLog.info("7-Zip", "opened …")`); the console window reads
/// `snapshot()` a few times a second. It keeps the last `capacity` lines in memory only, and
/// also forwards each line to the unified log (Console.app, Xcode) under the subsystem
/// `top.kitsune.zeig`. Safe to call from any thread, including the engines' worker threads.
public enum ZeigLog {
    public static let capacity = 2_000

    private struct Buffer {
        var entries: [LogEntry] = []
        var nextID: UInt64 = 0
    }

    private static let buffer = Mutex(Buffer())
    private static let logger = Logger(subsystem: "top.kitsune.zeig", category: "engines")

    public static func log(_ level: LogEntry.Level, _ source: String, _ message: String) {
        buffer.withLock { buffer in
            buffer.entries.append(LogEntry(id: buffer.nextID, date: .now, level: level, source: source, message: message))
            buffer.nextID += 1
            if buffer.entries.count > capacity { buffer.entries.removeFirst(buffer.entries.count - capacity) }
        }
        // While stdout/stderr are captured, don't also send to the unified log: under Xcode it
        // echoes to stderr, which would come straight back here as a second copy.
        guard !NativeOutputCapture.isRunning else { return }
        switch level {
        case .debug: logger.debug("[\(source, privacy: .public)] \(message, privacy: .public)")
        case .info: logger.info("[\(source, privacy: .public)] \(message, privacy: .public)")
        case .warning: logger.warning("[\(source, privacy: .public)] \(message, privacy: .public)")
        case .error: logger.error("[\(source, privacy: .public)] \(message, privacy: .public)")
        }
    }

    public static func debug(_ source: String, _ message: String) { log(.debug, source, message) }
    public static func info(_ source: String, _ message: String) { log(.info, source, message) }
    public static func warning(_ source: String, _ message: String) { log(.warning, source, message) }
    public static func error(_ source: String, _ message: String) { log(.error, source, message) }

    /// Every kept line, oldest first.
    public static func snapshot() -> [LogEntry] { buffer.withLock { $0.entries } }

    /// Goes up with every new line; cheap to poll.
    public static var lastID: UInt64 { buffer.withLock { $0.nextID } }

    public static func clear() { buffer.withLock { $0.entries.removeAll() } }

    /// The whole log as text, for sharing.
    public static func export() -> String {
        let format = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return snapshot().map { "\($0.date.formatted(format)) \($0.level.rawValue.uppercased()) [\($0.source)] \($0.message)" }
            .joined(separator: "\n")
    }

    /// Times `body` and logs how long it took (and its error, if any).
    public static func measure<T, E: Error>(_ source: String, _ what: String, _ body: () throws(E) -> T) throws(E) -> T {
        let start = ContinuousClock.now
        do {
            let result = try body()
            info(source, "\(what) — \(duration(since: start))")
            return result
        } catch {
            self.error(source, "\(what) failed after \(duration(since: start)): \(error)")
            throw error
        }
    }

    private static func duration(since start: ContinuousClock.Instant) -> String {
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        return ms < 1000 ? String(format: "%.0f ms", ms) : String(format: "%.2f s", ms / 1000)
    }
}
