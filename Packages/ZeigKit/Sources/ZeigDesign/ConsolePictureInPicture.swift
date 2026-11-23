#if os(iOS)
import AVFoundation
import AVKit
import CoreMedia
import Observation
import Synchronization
import UIKit
import ZeigCore

/// The developer console's live view in the system's picture-in-picture window: the latest log
/// lines, drawn as video frames. Display only; the full console is `ConsoleView`.
///
/// Why video: iOS's own PiP window is far better than anything an app can draw itself. It
/// floats over every app, can be resized, stashed at the edge and moved by the system, and
/// costs nothing while hidden. It only plays video, so this renders the log into pixel buffers
/// and feeds them to an `AVSampleBufferDisplayLayer` as a live stream:
///
/// 1. `prepare()` puts a 1-point view with the display layer behind the key window's content
///    (PiP needs the layer in a window, not visible), enqueues a first frame, and makes an
///    `AVPictureInPictureController` for it. It runs when developer mode is on, so the
///    controller is ready by the time of the tap, and it stays for the next time.
/// 2. `toggle()` follows `PictureInPictureState`: if the window isn't up, it brings it up.
///    Only iOS's own callbacks count as "on", because a start can fail without any callback;
///    a watchdog notices that, and retries with a new controller.
/// 3. While it's up, a new frame goes out when the log changes, and about once a second anyway
///    (iOS shows a spinner over a stream that has gone quiet).
/// 4. The window's pause button freezes the lines; its "back to app" button runs `onRestore`
///    (the app opens the full console).
///
/// PiP needs the audio session's playback category (mixing with other audio, so music keeps
/// playing) and the `audio` background mode in Info.plist. Starting it must follow a tap.
@MainActor
@Observable
public final class ConsolePictureInPicture: NSObject {
    public static let shared = ConsolePictureInPicture()

    public private(set) var state = PictureInPictureState()
    /// The user tapped the window's "back to app" button.
    @ObservationIgnored public var onRestore: (@MainActor () -> Void)?

    public static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    /// How long iOS gets to show or close the window before it counts as not happening.
    private static let patience: Duration = .seconds(2)

    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var layerView: DisplayLayerView?
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var lastRenderedID: UInt64 = .max
    /// Read by the playback delegate, which AVKit calls outside the main actor's knowledge.
    @ObservationIgnored private let paused = Mutex(false)

    /// Gets the controller ready ahead of the tap. Safe to call again.
    public func prepare() {
        guard Self.isSupported else { return }
        if controller != nil, layerView?.window != nil { return }
        discardController()
        guard let window = Self.keyWindow else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        } catch {
            ZeigLog.warning("console", "audio session: \(error.localizedDescription)")
        }
        let view = DisplayLayerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.isUserInteractionEnabled = false
        window.insertSubview(view, at: 0)
        layerView = view
        render(force: true)

        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: view.displayLayer, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.requiresLinearPlayback = true
        self.controller = controller
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] controller, _ in
            guard controller.isPictureInPicturePossible else { return }
            Task { @MainActor in self?.askToStart() }
        }
    }

    /// The control's press: brings the window up if it isn't up, closes it if it is.
    public func toggle() {
        guard Self.isSupported else {
            ZeigLog.warning("console", "picture in picture isn't supported here")
            return
        }
        // A callback may have been missed: believe the controller over the last known state.
        if controller?.isPictureInPictureActive == true {
            if state.phase != .on { state.systemStarted() }
        } else if state.phase == .on {
            perform(state.systemStopped())
        }
        perform(state.press())
    }

    /// Closes the window if it's up (developer mode turned off).
    public func stop() {
        perform(state.turnOff())
    }

    private func perform(_ action: PictureInPictureState.Action) {
        switch action {
        case .none:
            break
        case .start:
            begin()
        case .restart:
            discardController()
            begin()
        case .stop:
            controller?.stopPictureInPicture()
            startWatchdog()
        case .finish:
            finish()
        }
    }

    private func begin() {
        paused.withLock { $0 = false }
        ZeigLog.info("console", "picture in picture requested")
        prepare()
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            ZeigLog.warning("console", "audio session: \(error.localizedDescription)")
        }
        startRendering()
        askToStart()
        startWatchdog()
    }

    private func askToStart() {
        guard case .starting = state.phase, let controller,
              controller.isPictureInPicturePossible, !controller.isPictureInPictureActive else { return }
        controller.startPictureInPicture()
    }

    /// When iOS doesn't do what was asked in time: treat it as a failed start, or as closed.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.patience)
            guard !Task.isCancelled, let self else { return }
            switch state.phase {
            case .starting:
                ZeigLog.warning("console", "picture in picture didn't start in time")
                perform(state.attemptFailed())
            case .stopping:
                perform(state.systemStopped())
            case .off, .on:
                break
            }
        }
    }

    private func startRendering() {
        render(force: true)
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                tick += 1
                self?.render(force: tick % 3 == 0)
            }
        }
    }

    /// The window is gone. The controller stays, ready for the next press.
    private func finish() {
        watchdog?.cancel()
        watchdog = nil
        renderTask?.cancel()
        renderTask = nil
        if state.failed { ZeigLog.error("console", "picture in picture didn't start") }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func discardController() {
        possibleObservation = nil
        controller = nil
        layerView?.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true)
        layerView?.removeFromSuperview()
        layerView = nil
        lastRenderedID = .max
    }

    private func render(force: Bool) {
        guard let layer = layerView?.displayLayer, !paused.withLock({ $0 }) else { return }
        let id = ZeigLog.lastID
        guard force || id != lastRenderedID else { return }
        lastRenderedID = id
        let renderer = layer.sampleBufferRenderer
        // After the app comes back from the background the renderer needs a flush first.
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding { renderer.flush() }
        if let frame = ConsoleFrame.sampleBuffer(for: ZeigLog.snapshot()) {
            renderer.enqueue(frame)
        }
    }

    private static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow ?? scene?.windows.first
    }
}

extension ConsolePictureInPicture: AVPictureInPictureControllerDelegate {
    nonisolated public func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            watchdog?.cancel()
            state.systemStarted()
            ZeigLog.info("console", "picture in picture started")
        }
    }

    nonisolated public func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            watchdog?.cancel()
            perform(state.systemStopped())
            ZeigLog.info("console", "picture in picture closed")
        }
    }

    nonisolated public func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Error
    ) {
        MainActor.assumeIsolated {
            ZeigLog.warning("console", "picture in picture failed: \(error.localizedDescription)")
            perform(state.attemptFailed())
        }
    }

    nonisolated public func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        MainActor.assumeIsolated { onRestore?() }
        completionHandler(true)
    }
}

extension ConsolePictureInPicture: AVPictureInPictureSampleBufferPlaybackDelegate {
    /// The pause button freezes the lines on screen (new entries still go into the log).
    nonisolated public func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        paused.withLock { $0 = !playing }
        MainActor.assumeIsolated {
            // The stored controller (the same object): the parameter can't cross into the main actor.
            self.controller?.invalidatePlaybackState()
            if playing { render(force: true) }
        }
    }

    /// A live stream: no scrubber, no skip buttons.
    nonisolated public func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated public func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        paused.withLock { $0 }
    }

    nonisolated public func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated public func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

/// A view whose layer is the display layer PiP plays from.
private final class DisplayLayerView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
}

/// Draws the last lines of the log into one video frame.
@MainActor
enum ConsoleFrame {
    /// 3:2 at a resolution that stays sharp when the window is enlarged. The font is large
    /// because the default PiP window is small: about 14 lines fit.
    static let size = CGSize(width: 1200, height: 800)
    static let fontSize: CGFloat = 40
    static let padding: CGFloat = 28

    static func sampleBuffer(for entries: [LogEntry]) -> CMSampleBuffer? {
        guard let pixels = pixelBuffer(for: entries) else { return nil }
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels, formatDescriptionOut: &format)
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: pixels, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample
        )
        guard let sample else { return nil }
        // Show each frame as soon as it arrives instead of scheduling it by timestamp.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        return sample
    }

    private static func pixelBuffer(for entries: [LogEntry]) -> CVPixelBuffer? {
        let width = Int(size.width), height = Int(size.height)
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        // UIKit's coordinates: origin at the top left.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        draw(entries, in: context)
        return buffer
    }

    private static func draw(_ entries: [LogEntry], in context: CGContext) {
        context.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let lineHeight = font.lineHeight * 1.1
        let header = NSAttributedString(string: "Zeig! console · \(entries.count)", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: fontSize * 0.8, weight: .semibold),
            .foregroundColor: UIColor(white: 0.6, alpha: 1),
        ])
        header.draw(at: CGPoint(x: padding, y: padding))

        // Newest at the bottom, like a terminal.
        let top = padding + lineHeight * 1.2
        let rows = max(Int((size.height - top - padding) / lineHeight), 1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        for (row, entry) in entries.suffix(rows).enumerated() {
            let line = NSMutableAttributedString()
            line.append(NSAttributedString(string: entry.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)) + " ", attributes: [
                .foregroundColor: UIColor(white: 0.5, alpha: 1),
            ]))
            line.append(NSAttributedString(string: "\(entry.level.symbol) \(entry.source) ", attributes: [
                .foregroundColor: color(entry.level),
            ]))
            line.append(NSAttributedString(string: entry.message.replacingOccurrences(of: "\n", with: " "), attributes: [
                .foregroundColor: UIColor.white,
            ]))
            line.addAttributes([.font: font, .paragraphStyle: paragraph], range: NSRange(location: 0, length: line.length))
            let rect = CGRect(x: padding, y: top + CGFloat(row) * lineHeight, width: size.width - padding * 2, height: lineHeight)
            line.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }
        if entries.isEmpty {
            NSAttributedString(string: "No entries yet", attributes: [.font: font, .foregroundColor: UIColor(white: 0.5, alpha: 1)])
                .draw(at: CGPoint(x: padding, y: top))
        }
    }

    private static func color(_ level: LogEntry.Level) -> UIColor {
        switch level {
        case .debug: .systemGray
        case .info: .systemCyan
        case .warning: .systemYellow
        case .error: .systemRed
        }
    }
}
#endif
