import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A kind of text in the app, each with its own font in Settings → Developer → Font Lab.
public enum FontRole: String, CaseIterable, Identifiable, Sendable {
    /// Large page titles ("Browse", a folder's name, "Search") and sheet titles.
    case title
    /// File, folder and archive-entry names in lists.
    case fileName
    /// Lines under names and titles: sizes, dates, item counts.
    case subtitle
    /// Small labels that mark or count: badges, the scope switch, capsule buttons, counts.
    case indicator
    /// Explanations: the create sheet's summaries, the Format Guide, footers.
    case guide

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .title: "Titles"
        case .fileName: "File names"
        case .subtitle: "Subtitles"
        case .indicator: "Indicators"
        case .guide: "Guide text"
        }
    }

    public var explanation: String {
        switch self {
        case .title: "Page titles like Browse, Recent and a folder's name."
        case .fileName: "Names of files, folders and items inside archives."
        case .subtitle: "Size, date and count lines under names and titles."
        case .indicator: "Badges, the search switch, capsule buttons and counts."
        case .guide: "Explanations in the create sheet and the Format Guide."
        }
    }

    /// The text style and weight a role uses unless a view asks for another.
    public var defaultStyle: Font.TextStyle {
        switch self {
        case .title: .largeTitle
        case .fileName: .body
        case .subtitle: .caption
        case .indicator: .subheadline
        case .guide: .footnote
        }
    }

    public var defaultWeight: Font.Weight {
        switch self {
        case .title: .bold
        case .indicator: .semibold
        default: .regular
        }
    }
}

/// A typeface. Stored as a short string `id` so `AppSettings` (no SwiftUI) can keep it.
public enum FontFace: Hashable, Sendable, Identifiable {
    case system
    /// New York.
    case serif
    case rounded
    /// SF Mono.
    case monospaced
    /// Any font family installed on the device.
    case installed(family: String)

    public static let builtIn: [FontFace] = [.system, .rounded, .serif, .monospaced]

    public var id: String {
        switch self {
        case .system: "system"
        case .serif: "serif"
        case .rounded: "rounded"
        case .monospaced: "monospaced"
        case .installed(let family): "family:\(family)"
        }
    }

    /// Parses an `id`; unknown IDs return `nil` so callers fall back to the default.
    public init?(id: String) {
        if id.hasPrefix("family:") {
            self = .installed(family: String(id.dropFirst("family:".count)))
            return
        }
        guard let face = Self.builtIn.first(where: { $0.id == id }) else { return nil }
        self = face
    }

    public var name: String {
        switch self {
        case .system: "System (SF Pro)"
        case .serif: "New York"
        case .rounded: "SF Rounded"
        case .monospaced: "SF Mono"
        case .installed(let family): family
        }
    }

    /// This face at `style` times `scale`, following Dynamic Type.
    public func font(_ style: Font.TextStyle, weight: Font.Weight, scale: Double = 1) -> Font {
        let design: Font.Design? = switch self {
        case .system: .default
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        case .installed: nil
        }
        if let design {
            if scale == 1 { return .system(style, design: design, weight: weight) }
            // A scaled system font has a fixed size (SwiftUI can't scale a system text style
            // by a factor); the scale is a Font Lab experiment, so that's acceptable.
            return .system(size: style.defaultPointSize * scale, weight: weight, design: design)
        }
        guard case .installed(let family) = self else { return .system(style) }
        return .custom(family, size: style.defaultPointSize * scale, relativeTo: style).weight(weight)
    }

    /// Every font family installed on this device, sorted, for the Font Lab.
    @MainActor
    public static var installedFamilies: [String] {
        #if canImport(UIKit)
        UIFont.familyNames.sorted()
        #else
        []
        #endif
    }
}

/// Which face and size each `FontRole` uses. Read it with `@Environment(\.fontTheme)` and ask
/// for a role: `fonts.font(.fileName)`, or `fonts.font(.subtitle, .subheadline)` to change the
/// text style but keep the role's face and scale. The app builds it from `AppSettings`
/// (`fontFaceIDs`, `fontScales`), which the Font Lab edits.
public struct FontTheme: Hashable, Sendable {
    public var faces: [FontRole: FontFace]
    public var scales: [FontRole: Double]

    public static let standard = FontTheme(faces: [:], scales: [:])

    public init(faces: [FontRole: FontFace], scales: [FontRole: Double]) {
        self.faces = faces
        self.scales = scales
    }

    /// From stored IDs (role raw value → face ID / scale). Unknown entries are ignored.
    public init(faceIDs: [String: String], scales: [String: Double]) {
        var faces: [FontRole: FontFace] = [:]
        for (role, id) in faceIDs {
            if let role = FontRole(rawValue: role), let face = FontFace(id: id) { faces[role] = face }
        }
        var roleScales: [FontRole: Double] = [:]
        for (role, scale) in scales {
            if let role = FontRole(rawValue: role) { roleScales[role] = scale }
        }
        self.init(faces: faces, scales: roleScales)
    }

    public func face(_ role: FontRole) -> FontFace { faces[role] ?? .system }
    public func scale(_ role: FontRole) -> Double { scales[role] ?? 1 }

    public func font(_ role: FontRole, _ style: Font.TextStyle? = nil, weight: Font.Weight? = nil) -> Font {
        face(role).font(style ?? role.defaultStyle, weight: weight ?? role.defaultWeight, scale: scale(role))
    }
}

public extension EnvironmentValues {
    @Entry var fontTheme = FontTheme.standard
}

public extension Font.TextStyle {
    /// The point size of this style at the default (Large) Dynamic Type setting.
    var defaultPointSize: CGFloat {
        switch self {
        case .extraLargeTitle: 36
        case .extraLargeTitle2: 28
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}
