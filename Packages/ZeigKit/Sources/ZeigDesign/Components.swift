import SwiftUI
import ZeigCore

/// A full-width glass switch as tall as the header controls, with the selection as a pill
/// that slides between the sides (Photos' switch, not a segmented control). From HNReader's
/// Search tab, made generic.
public struct ScopeSwitcher<Option: Hashable & Identifiable>: View {
    @Binding private var selection: Option
    private let options: [Option]
    private let label: (Option) -> String
    @Environment(\.fontTheme) private var fonts

    public init(selection: Binding<Option>, options: [Option], label: @escaping (Option) -> String) {
        _selection = selection
        self.options = options
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(fonts.font(.indicator))
                        .foregroundStyle(selection == option ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .background(alignment: .leading) {
            GeometryReader { proxy in
                let width = proxy.size.width / CGFloat(max(options.count, 1))
                Capsule()
                    .fill(.fill.secondary)
                    .frame(width: width)
                    .offset(x: width * CGFloat(options.firstIndex(of: selection) ?? 0))
            }
        }
        .animation(.snappy(duration: 0.3), value: selection)
        .padding(4)
        .frame(height: pageHeaderControlSize)
        .hnGlass(in: Capsule(), interactive: true)
    }
}

#if os(iOS)
/// A large title as the leading toolbar item, without the glass background toolbar items get
/// on 26+, so it reads as a title on the same row as the trailing buttons (Search's header,
/// which keeps the system bar because the search tab won't hide it).
public struct LargeTitleItem: ToolbarContent {
    private let title: String
    @Environment(\.fontTheme) private var fonts

    public init(_ title: String) {
        self.title = title
    }

    public var body: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: .topBarLeading) { label }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { label }
        }
    }

    private var label: some View {
        Text(title)
            .font(fonts.font(.title))
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }
}
#endif

/// The SF Symbol for a file in lists.
public enum FileSymbol {
    public static func name(isDirectory: Bool, format: ArchiveFormat?, fileName: String) -> String {
        if isDirectory { return "folder.fill" }
        if let format {
            switch format {
            case .iso, .dmg, .vhd, .vmdk, .squashfs: return "opticaldiscdrive"
            case .deb, .rpm, .msi, .xar: return "shippingbox"
            default: return "doc.zipper"
            }
        }
        switch (fileName as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "webp", "tiff": return "photo"
        case "mov", "mp4", "m4v": return "film"
        case "mp3", "m4a", "wav", "flac", "aac": return "music.note"
        case "pdf": return "doc.richtext"
        case "txt", "md", "rtf", "log", "csv": return "doc.text"
        case "swift", "c", "h", "cpp", "rs", "py", "js", "json", "html", "css", "sh": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}

/// A round icon tile for file rows.
public struct FileIcon: View {
    private let symbol: String
    private let tint: Color

    public init(isDirectory: Bool, format: ArchiveFormat?, fileName: String) {
        symbol = FileSymbol.name(isDirectory: isDirectory, format: format, fileName: fileName)
        // Folders in the system blue, archives in Zeig's orange, so the two never blur together.
        tint = isDirectory ? .blue : (format != nil ? .orange : .secondary)
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The orange "Experimental" tag next to anything that uses the rars backend.
public struct ExperimentalBadge: View {
    @Environment(\.fontTheme) private var fonts

    public init() {}

    public var body: some View {
        Text("Experimental")
            .font(fonts.font(.indicator, .caption2))
            .textCase(.uppercase)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.orange)
            .background(.orange.opacity(0.15), in: Capsule())
    }
}

public extension UInt64 {
    /// "1.2 MB".
    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: self), countStyle: .file)
    }
}

/// Opens the Settings sheet. Set by the app; every tab's header calls it.
public struct ShowSettingsAction {
    private let action: @MainActor () -> Void

    public init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @MainActor public func callAsFunction() { action() }
}

public extension EnvironmentValues {
    @Entry var showSettings = ShowSettingsAction {}
}

public extension View {
    /// Small inline navigation title on iOS (pushed screens); nothing on macOS, which only
    /// builds this package for tests.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
