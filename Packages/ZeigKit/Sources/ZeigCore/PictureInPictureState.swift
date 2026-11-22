/// What pressing the console's picture-in-picture control means, and what's going on with the
/// window. The rule: **if the window isn't up, a press brings it up.**
///
/// Kept apart from AVKit (`ConsolePictureInPicture` in ZeigDesign follows these decisions)
/// because iOS can fail to start picture in picture without saying so, and the window takes a
/// moment to close. So "on" is only what iOS has confirmed:
/// - a press while starting tries again instead of cancelling;
/// - a press while closing starts again as soon as the window is gone;
/// - when a start doesn't happen, it retries with a new controller, then goes back to off so
///   the next press starts cleanly.
public struct PictureInPictureState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case off
        case starting(attempt: Int)
        case on
        case stopping(restartAfterwards: Bool)
    }

    /// What the owner of the AVKit controller should do next.
    public enum Action: Sendable, Equatable {
        case none
        /// Ask iOS to show the window.
        case start
        /// Throw the controller away and ask again with a new one.
        case restart
        /// Ask iOS to close the window.
        case stop
        /// The window is gone or never came: stop drawing and release the audio session.
        case finish
    }

    /// Tries per press before giving up.
    public static let maxAttempts = 2

    public private(set) var phase = Phase.off
    /// The last start gave up. Cleared by the next press.
    public private(set) var failed = false

    public init() {}

    /// The switch's position: on while the window is up or on its way.
    public var showsOn: Bool {
        switch phase {
        case .off, .stopping(restartAfterwards: false): false
        case .starting, .on, .stopping(restartAfterwards: true): true
        }
    }

    public mutating func press() -> Action {
        switch phase {
        case .off:
            failed = false
            phase = .starting(attempt: 1)
            return .start
        case .starting:
            phase = .starting(attempt: 1)
            return .restart
        case .on:
            phase = .stopping(restartAfterwards: false)
            return .stop
        case .stopping:
            phase = .stopping(restartAfterwards: true)
            return .none
        }
    }

    /// Close the window, or abandon a start, without restarting (developer mode turned off).
    public mutating func turnOff() -> Action {
        switch phase {
        case .off:
            return .none
        case .starting:
            phase = .off
            return .finish
        case .on:
            phase = .stopping(restartAfterwards: false)
            return .stop
        case .stopping:
            phase = .stopping(restartAfterwards: false)
            return .none
        }
    }

    /// iOS is showing the window.
    public mutating func systemStarted() {
        phase = .on
        failed = false
    }

    /// iOS closed the window, however that came about (its own close button, "back to app",
    /// or a stop that was asked for).
    public mutating func systemStopped() -> Action {
        switch phase {
        case .stopping(restartAfterwards: true):
            phase = .starting(attempt: 1)
            return .start
        case .starting:
            // The end of an earlier window; the start in progress carries on.
            return .none
        case .off:
            return .none
        case .on, .stopping(restartAfterwards: false):
            phase = .off
            return .finish
        }
    }

    /// iOS reported a failure, or the window didn't appear in time.
    public mutating func attemptFailed() -> Action {
        guard case .starting(let attempt) = phase else { return .none }
        if attempt < Self.maxAttempts {
            phase = .starting(attempt: attempt + 1)
            return .restart
        }
        phase = .off
        failed = true
        return .finish
    }
}
