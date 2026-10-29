import SwiftUI
import UniformTypeIdentifiers
import ZeigCore

/// The full developer console, as a sheet: every log line, live, with search, a level filter,
/// and share, export and clear. Opened from the console button in the Browse and Recent
/// headers (developer mode only), from Settings → Developer, and from the picture-in-picture
/// window's "back to app" button.
public struct ConsoleView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [LogEntry] = []
    @State private var lastID: UInt64 = .max
    @State private var minimumLevel: LogEntry.Level = .debug
    @State private var query = ""
    @State private var isExporting = false
    @State private var followsNewest = true

    public init() {}

    private var visible: [LogEntry] {
        let order = LogEntry.Level.allCases
        let minimum = order.firstIndex(of: minimumLevel) ?? 0
        return entries.filter { entry in
            (order.firstIndex(of: entry.level) ?? 0) >= minimum
                && (query.isEmpty || entry.message.localizedCaseInsensitiveContains(query)
                    || entry.source.localizedCaseInsensitiveContains(query))
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(visible) { entry in
                    ConsoleLine(entry: entry)
                        .id(entry.id)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                .listStyle(.plain)
                .overlay {
                    if visible.isEmpty {
                        ContentUnavailableView(entries.isEmpty ? "No Entries" : "No Matches", systemImage: "terminal")
                    }
                }
                .onChange(of: visible.last?.id) { _, id in
                    guard followsNewest, let id else { return }
                    withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(id, anchor: .bottom) }
                }
                .onAppear {
                    if let id = visible.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .searchable(text: $query, prompt: "Messages and sources")
            .navigationTitle("Console")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) { menu }
            }
            .logExporter(isPresented: $isExporting)
        }
        .task {
            // Poll a few times a second: cheap, and keeps engine threads off the main actor.
            while !Task.isCancelled {
                let id = ZeigLog.lastID
                if id != lastID {
                    lastID = id
                    entries = ZeigLog.snapshot()
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    private var menu: some View {
        Menu("Options", systemImage: "ellipsis") {
            Picker("Show", selection: $minimumLevel) {
                ForEach(LogEntry.Level.allCases, id: \.self) { level in
                    Text(level == .debug ? "Everything" : level.rawValue.capitalized + " and Up").tag(level)
                }
            }
            Toggle("Follow Newest", systemImage: "arrow.down.to.line", isOn: $followsNewest)
            #if os(iOS)
            if ConsolePictureInPicture.isSupported {
                Button(
                    ConsolePictureInPicture.shared.isActive ? "Close Picture in Picture" : "Picture in Picture",
                    systemImage: "pip"
                ) { ConsolePictureInPicture.shared.toggle() }
            }
            #endif
            Divider()
            ShareLink(item: ZeigLog.export()) { Label("Share Log", systemImage: "square.and.arrow.up") }
            Button("Export Log…", systemImage: "square.and.arrow.down") { isExporting = true }
            Button("Clear Log", systemImage: "trash", role: .destructive) {
                ZeigLog.clear()
                entries = []
            }
        }
    }
}

/// One log line: time, level and source in color, then the message.
private struct ConsoleLine: View {
    let entry: LogEntry

    var body: some View {
        (Text(entry.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second()) + " ")
            .foregroundStyle(.secondary)
         + Text("\(entry.level.symbol) [\(entry.source)] ").foregroundStyle(color)
         + Text(entry.message))
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var color: Color {
        switch entry.level {
        case .debug: .gray
        case .info: .cyan
        case .warning: .orange
        case .error: .red
        }
    }
}

public extension View {
    /// Saves the log as a text file wherever the user picks (Files, iCloud Drive, …).
    func logExporter(isPresented: Binding<Bool>) -> some View {
        fileExporter(
            isPresented: isPresented,
            item: isPresented.wrappedValue ? ZeigLog.export() : nil,
            contentTypes: [.plainText],
            defaultFilename: "Zeig Log \(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))"
        ) { result in
            switch result {
            case .success(let url): ZeigLog.info("console", "log exported to \(url.lastPathComponent)")
            case .failure(let error): ZeigLog.error("console", "export failed: \(error.localizedDescription)")
            }
        }
    }
}

/// Opens the console sheet. Set by the app; the Browse and Recent headers call it.
public struct ShowConsoleAction {
    private let action: @MainActor () -> Void

    public init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @MainActor public func callAsFunction() { action() }
}

public extension EnvironmentValues {
    @Entry var showConsole = ShowConsoleAction {}
}
