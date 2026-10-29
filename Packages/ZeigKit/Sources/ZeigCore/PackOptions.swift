import Foundation

/// How hard to compress. Each backend maps these to its own scale (`level(in:)`).
public enum CompressionLevel: Int, CaseIterable, Sendable, Codable, Identifiable, Comparable {
    case store, fastest, fast, normal, maximum, ultra

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .store: "Store (no compression)"
        case .fastest: "Fastest"
        case .fast: "Fast"
        case .normal: "Normal"
        case .maximum: "Maximum"
        case .ultra: "Ultra"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The level on a numeric scale `range`, spread so `.normal` lands in the middle: 5 on
    /// 7-Zip's, gzip's and xz's 0…9, 3 on RAR's 0…5. Scales whose default isn't the middle
    /// (zstd's 1…22, default 3) map the levels themselves.
    public func level(in range: ClosedRange<Int>) -> Int {
        let fraction: Double = switch self {
        case .store: 0
        case .fastest: 0.12
        case .fast: 0.34
        case .normal: 0.56
        case .maximum: 0.78
        case .ultra: 1
        }
        return range.lowerBound + Int((Double(range.count - 1) * fraction).rounded())
    }
}

/// One setting in the create sheet's "Advanced settings" for a format.
///
/// `id` is stable (it's stored with the user's last choices) and is what the backends read in
/// `PackRequest.advanced`. `summary` is the one-line explanation shown under the control;
/// `guide` is the topic with the full explanation (Settings → Format Guide, or the ⓘ button).
public struct FormatOption: Sendable, Identifiable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// One of fixed values. The first is the default unless `defaultValue` says otherwise.
        case choice([Choice])
        case toggle
        case text(placeholder: String)
    }

    public struct Choice: Sendable, Hashable, Identifiable {
        public var value: String
        public var label: String
        public var id: String { value }

        public init(_ value: String, _ label: String) {
            self.value = value
            self.label = label
        }
    }

    public var id: String
    public var title: String
    public var summary: String
    public var kind: Kind
    public var defaultValue: String
    public var guide: GuideTopic.ID
    /// Only meaningful with a password (greyed out without one).
    public var needsPassword: Bool

    public init(
        id: String, title: String, summary: String, kind: Kind, defaultValue: String? = nil,
        guide: GuideTopic.ID, needsPassword: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.kind = kind
        self.guide = guide
        self.needsPassword = needsPassword
        if let defaultValue {
            self.defaultValue = defaultValue
        } else if case .choice(let choices) = kind, let first = choices.first {
            self.defaultValue = first.value
        } else if case .toggle = kind {
            self.defaultValue = "off"
        } else {
            self.defaultValue = ""
        }
    }
}

/// Everything needed to create an archive.
public struct PackRequest: Sendable {
    /// The archive file to write. For split archives, the first volume's name is derived from it.
    public var destination: URL
    /// Files and folders to add. Folders are added with everything inside; each source is
    /// named in the archive relative to its parent folder.
    public var sources: [URL]
    public var format: ArchiveFormat
    public var level: CompressionLevel
    /// Only for formats where `supportsPassword`. `nil` or empty means no encryption.
    public var password: String?
    /// Advanced settings by `FormatOption.id`; missing ones use the option's default.
    public var advanced: [String: String]

    public init(
        destination: URL, sources: [URL], format: ArchiveFormat, level: CompressionLevel = .normal,
        password: String? = nil, advanced: [String: String] = [:]
    ) {
        self.destination = destination
        self.sources = sources
        self.format = format
        self.level = level
        self.password = password
        self.advanced = advanced
    }

    /// The password, or `nil` if empty or the format can't use one.
    public var effectivePassword: String? {
        guard format.supportsPassword, let password, !password.isEmpty else { return nil }
        return password
    }

    /// An advanced value, or that option's default.
    public func value(_ optionID: String) -> String {
        if let value = advanced[optionID] { return value }
        return FormatOptions.options(for: format).first { $0.id == optionID }?.defaultValue ?? ""
    }

    public func isOn(_ optionID: String) -> Bool { value(optionID) == "on" }
}
