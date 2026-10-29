import Foundation
import Observation
import SwiftUI
import ZeigBackends
import ZeigCore
import ZeigDesign
import ZeigStore

/// An alert's text, with the backend's own message tucked under "Details".
public struct AlertContent: Identifiable {
    public let id = UUID()
    public var title: String
    public var message: String
    public var detail: String?

    public init(title: String, message: String, detail: String? = nil) {
        self.title = title
        self.message = message
        self.detail = detail
    }

    init(_ title: String, _ error: ArchiveError) {
        self.init(title: title, message: error.message, detail: error.detail)
    }
}

/// The archive operations a screen offers (open, extract, test), with what they need around
/// them: progress, asking for a password and retrying, error alerts, and recording Recent.
/// Each screen owns one and attaches `.archiveActions(_:)` to show its UI.
@MainActor
@Observable
public final class ArchiveActions {
    public let operation = OperationModel()
    public var alert: AlertContent?
    public var passwordPrompt: PasswordPrompt?
    /// Set after a successful extraction, for the "Extracted" confirmation.
    public var extracted: URL?

    /// A pending password question; the alert answers through `answer(_:)`.
    public struct PasswordPrompt: Identifiable {
        public let id = UUID()
        public var archiveName: String
        public var wasWrong: Bool
        fileprivate var continuation: CheckedContinuation<String?, Never>

        public func answer(_ password: String?) { continuation.resume(returning: password) }
    }

    public init() {}

    /// Runs `body` without a password, then asks for one and retries for as long as the
    /// archive says it needs one (or the password was wrong). `nil` if the user cancels.
    public func withPassword<T>(
        for url: URL, initial: String? = nil,
        _ body: (String?) async throws(ArchiveError) -> T
    ) async throws(ArchiveError) -> (value: T, password: String?)? {
        var password = initial
        while true {
            do {
                return (try await body(password), password)
            } catch .passwordRequired {
                password = await askPassword(for: url, wasWrong: false)
            } catch .wrongPassword {
                password = await askPassword(for: url, wasWrong: true)
            }
            if password == nil { return nil }
        }
    }

    private func askPassword(for url: URL, wasWrong: Bool) async -> String? {
        await withCheckedContinuation { continuation in
            passwordPrompt = PasswordPrompt(archiveName: url.lastPathComponent, wasWrong: wasWrong, continuation: continuation)
        }
    }

    /// Opens (lists) an archive, asking for a password if needed.
    public func open(_ url: URL, service: ArchiveService) async -> (ArchiveListing, String?)? {
        do {
            return try await withPassword(for: url) { (password) throws(ArchiveError) in
                try await service.open(url, password: password)
            }
        } catch {
            alert = AlertContent("Can't open \(url.lastPathComponent)", error)
            return nil
        }
    }

    /// Extracts everything (or `entries`) into a new folder next to the archive.
    public func extract(
        _ url: URL, listing: ArchiveListing? = nil, entries: [ArchiveEntry]? = nil, password: String? = nil,
        service: ArchiveService, library: FileLibrary, recent: RecentStore
    ) async {
        do {
            let result = try await withPassword(for: url, initial: password) { (password) throws(ArchiveError) -> URL in
                let opened: ArchiveListing
                if let listing {
                    opened = listing
                } else {
                    opened = try await service.open(url, password: password)
                }
                return try await operation.run("Extracting…") { (progress) throws(ArchiveError) in
                    try await service.extractToNewFolder(opened, entries: entries, password: password, progress: progress)
                }
            }
            guard let folder = result?.value else { return }
            library.noteChange()
            recent.record(library.relativePath(of: folder), .extracted)
            extracted = folder
        } catch .cancelled {
            library.noteChange()
        } catch {
            alert = AlertContent("Can't extract \(url.lastPathComponent)", error)
        }
    }

    /// Decompresses everything and reports whether it's intact.
    public func test(_ listing: ArchiveListing, password: String?, service: ArchiveService) async {
        do {
            try await operation.run("Testing…") { (progress) throws(ArchiveError) in
                try await service.test(listing, password: password, progress: progress)
            }
            alert = AlertContent(title: "No errors found", message: "Every file in \(listing.url.lastPathComponent) decompressed and matched its checksum.")
        } catch .cancelled {
        } catch {
            alert = AlertContent("\(listing.url.lastPathComponent) has errors", error)
        }
    }
}

public extension View {
    /// The progress overlay, password prompt and alerts for `actions`.
    func archiveActions(_ actions: ArchiveActions) -> some View {
        modifier(ArchiveActionsUI(actions: actions))
    }
}

private struct ArchiveActionsUI: ViewModifier {
    @Bindable var actions: ArchiveActions
    @State private var password = ""

    func body(content: Content) -> some View {
        content
            .overlay { OperationOverlay(actions.operation) }
            .animation(.default, value: actions.operation.isRunning)
            .alert(
                actions.passwordPrompt?.wasWrong == true ? "Wrong password" : "Password needed",
                isPresented: Binding(get: { actions.passwordPrompt != nil }, set: { if !$0 { finishPrompt(nil) } })
            ) {
                SecureField("Password", text: $password)
                Button("Cancel", role: .cancel) { finishPrompt(nil) }
                Button("OK") { finishPrompt(password) }
            } message: {
                if let prompt = actions.passwordPrompt {
                    Text(prompt.wasWrong ? "Try again for “\(prompt.archiveName)”." : "“\(prompt.archiveName)” is protected with a password.")
                }
            }
            .alert(
                actions.alert?.title ?? "",
                isPresented: Binding(get: { actions.alert != nil }, set: { if !$0 { actions.alert = nil } }),
                presenting: actions.alert
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { alert in
                // The backend's own words go last, for bug reports.
                Text(alert.detail.map { alert.message + "\n\n" + $0 } ?? alert.message)
            }
    }

    private func finishPrompt(_ answer: String?) {
        guard let prompt = actions.passwordPrompt else { return }
        actions.passwordPrompt = nil
        password = ""
        prompt.answer(answer)
    }
}
