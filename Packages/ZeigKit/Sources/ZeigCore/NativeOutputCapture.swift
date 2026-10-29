import Foundation
import Synchronization

/// Copies everything the process writes to stdout and stderr (native code's `printf`,
/// Rust's `eprintln!`, Swift's `print`) into `ZeigLog`, while still passing it through to
/// the original output (Xcode's console).
///
/// It works by pointing file descriptors 1 and 2 at pipes and reading those on background
/// threads. Developer mode turns it on (Settings → Developer → Capture native output).
public enum NativeOutputCapture {
    private struct Redirect: Sendable {
        let fd: Int32
        let saved: Int32
        let readEnd: Int32
    }

    private static let redirects = Mutex<[Redirect]>([])

    public static var isRunning: Bool { redirects.withLock { !$0.isEmpty } }

    public static func start() {
        redirects.withLock { redirects in
            guard redirects.isEmpty else { return }
            setvbuf(stdout, nil, _IOLBF, 0)
            setvbuf(stderr, nil, _IONBF, 0)
            for (fd, name) in [(STDOUT_FILENO, "stdout"), (STDERR_FILENO, "stderr")] {
                var ends: [Int32] = [0, 0]
                guard pipe(&ends) == 0 else { continue }
                let saved = dup(fd)
                dup2(ends[1], fd)
                close(ends[1])
                let readEnd = ends[0]
                redirects.append(Redirect(fd: fd, saved: saved, readEnd: readEnd))
                let thread = Thread { pump(readEnd: readEnd, passThrough: saved, source: name) }
                thread.name = "Zeig \(name) capture"
                thread.start()
            }
        }
        ZeigLog.info("console", "Capturing stdout and stderr")
    }

    public static func stop() {
        redirects.withLock { redirects in
            for redirect in redirects {
                fflush(redirect.fd == STDOUT_FILENO ? stdout : stderr)
                dup2(redirect.saved, redirect.fd)
                // The pump thread sees end-of-file now that nothing writes into the pipe, and
                // closes the saved descriptor itself once it has passed everything through.
            }
            redirects.removeAll()
        }
        ZeigLog.info("console", "Stopped capturing stdout and stderr")
    }

    /// Reads lines from the pipe until it closes, logging each and passing the bytes on.
    private static func pump(readEnd: Int32, passThrough: Int32, source: String) {
        var pending = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(readEnd, &chunk, chunk.count)
            if count <= 0 { break }
            _ = chunk.withUnsafeBytes { write(passThrough, $0.baseAddress, count) }
            pending.append(contentsOf: chunk[0..<count])
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...newline)
                if !line.isEmpty { ZeigLog.log(source == "stderr" ? .warning : .debug, source, line) }
            }
        }
        close(readEnd)
        close(passThrough)
    }
}
