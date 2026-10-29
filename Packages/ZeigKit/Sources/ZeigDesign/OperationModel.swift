import Foundation
import Observation
import Synchronization
import SwiftUI
import ZeigCore

/// Progress and cancellation for one long operation (extracting, creating, testing), shown
/// by `OperationOverlay`.
///
/// Backends report progress on their own thread, often thousands of times a second. The
/// reporter keeps the latest numbers in a lock and the overlay reads them a few times a
/// second, so the main actor isn't flooded.
@MainActor
@Observable
public final class OperationModel {
    public private(set) var title: String?
    public var isRunning: Bool { title != nil }

    private let counters = Counters()

    public init() {}

    /// Runs `work` with a progress reporter, showing the overlay until it finishes.
    public func run<T, E: Error>(_ title: String, _ work: (ArchiveProgress) async throws(E) -> T) async throws(E) -> T {
        counters.reset()
        self.title = title
        defer { self.title = nil }
        let counters = counters
        let progress = ArchiveProgress { completed, total in
            counters.update(completed, total)
            return !counters.isCancelled
        }
        return try await work(progress)
    }

    public func cancel() { counters.cancel() }

    /// 0…1, or `nil` while the total is unknown.
    public var fraction: Double? { counters.fraction }

    public var isCancelling: Bool { counters.isCancelled }

    /// Thread-safe numbers shared with the backend's thread.
    private final class Counters: Sendable {
        private struct State {
            var completed: UInt64 = 0
            var total: UInt64 = 0
            var cancelled = false
        }

        private let state = Mutex(State())

        func reset() { state.withLock { $0 = State() } }
        func update(_ completed: UInt64, _ total: UInt64) {
            state.withLock {
                $0.completed = completed
                $0.total = total
            }
        }
        func cancel() { state.withLock { $0.cancelled = true } }
        var isCancelled: Bool { state.withLock { $0.cancelled } }
        var fraction: Double? {
            state.withLock { $0.total > 0 ? min(1, Double($0.completed) / Double($0.total)) : nil }
        }
    }
}

/// A card over the screen while an operation runs: title, progress bar, Cancel.
public struct OperationOverlay: View {
    private let model: OperationModel

    public init(_ model: OperationModel) {
        self.model = model
    }

    public var body: some View {
        if let title = model.title {
            ZStack {
                Color.black.opacity(0.15).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text(title).font(.headline)
                    // Polls the lock-protected numbers; see OperationModel.
                    TimelineView(.periodic(from: .now, by: 0.15)) { _ in
                        if let fraction = model.fraction {
                            ProgressView(value: fraction)
                        } else {
                            ProgressView()
                        }
                    }
                    Button(model.isCancelling ? "Cancelling…" : "Cancel", role: .cancel) { model.cancel() }
                        .disabled(model.isCancelling)
                }
                .padding(20)
                .frame(maxWidth: 320)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(32)
            }
            .transition(.opacity)
        }
    }
}
