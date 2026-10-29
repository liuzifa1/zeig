import Foundation
import Observation
import ZeigCore

/// The user's settings, saved in UserDefaults. Shared through the SwiftUI environment.
@MainActor
@Observable
public final class AppSettings {
    private let defaults: UserDefaults

    /// Settings → Experimental → "Test RAR backend": rars creates RAR archives.
    public var rarsEnabled: Bool {
        didSet { defaults.set(rarsEnabled, forKey: Keys.rarsEnabled) }
    }

    /// Settings → Experimental → "Use test RAR backend for opening RAR too".
    public var rarsOpensRar: Bool {
        didSet { defaults.set(rarsOpensRar, forKey: Keys.rarsOpensRar) }
    }

    /// Preselected in the create sheet.
    public var defaultFormat: ArchiveFormat {
        didSet { defaults.set(defaultFormat.rawValue, forKey: Keys.defaultFormat) }
    }

    public var defaultLevel: CompressionLevel {
        didSet { defaults.set(defaultLevel.rawValue, forKey: Keys.defaultLevel) }
    }

    /// The last advanced settings used per format, so the sheet remembers them.
    public private(set) var advancedByFormat: [ArchiveFormat: [String: String]] {
        didSet {
            let encoded = Dictionary(uniqueKeysWithValues: advancedByFormat.map { ($0.key.rawValue, $0.value) })
            defaults.set(encoded, forKey: Keys.advanced)
        }
    }

    /// Settings → Developer appears after tapping the version seven times.
    public var developerMode: Bool {
        didSet { defaults.set(developerMode, forKey: Keys.developerMode) }
    }

    /// Developer → Capture native output: stdout/stderr go into the console too.
    public var capturesNativeOutput: Bool {
        didSet { defaults.set(capturesNativeOutput, forKey: Keys.capturesNativeOutput) }
    }

    /// Font Lab: font face ID per text role (`FontRole.rawValue` → `FontFace.id`).
    public var fontFaceIDs: [String: String] {
        didSet { defaults.set(fontFaceIDs, forKey: Keys.fontFaces) }
    }

    /// Font Lab: size scale per text role (1 = normal).
    public var fontScales: [String: Double] {
        didSet { defaults.set(fontScales, forKey: Keys.fontScales) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rarsEnabled = defaults.bool(forKey: Keys.rarsEnabled)
        rarsOpensRar = defaults.bool(forKey: Keys.rarsOpensRar)
        defaultFormat = defaults.string(forKey: Keys.defaultFormat).flatMap(ArchiveFormat.init(rawValue:)) ?? .zip
        defaultLevel = CompressionLevel(rawValue: defaults.object(forKey: Keys.defaultLevel) as? Int ?? -1) ?? .normal
        developerMode = defaults.bool(forKey: Keys.developerMode)
        capturesNativeOutput = defaults.bool(forKey: Keys.capturesNativeOutput)
        fontFaceIDs = defaults.dictionary(forKey: Keys.fontFaces) as? [String: String] ?? [:]
        fontScales = defaults.dictionary(forKey: Keys.fontScales) as? [String: Double] ?? [:]
        let stored = defaults.dictionary(forKey: Keys.advanced) as? [String: [String: String]] ?? [:]
        advancedByFormat = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            ArchiveFormat(rawValue: key).map { ($0, value) }
        })
    }

    /// What the router needs from the settings.
    public var routing: RoutingSettings {
        RoutingSettings(rarsEnabled: rarsEnabled, rarsOpensRar: rarsOpensRar)
    }

    public func advanced(for format: ArchiveFormat) -> [String: String] {
        advancedByFormat[format] ?? [:]
    }

    public func remember(_ values: [String: String], for format: ArchiveFormat) {
        advancedByFormat[format] = values
    }

    enum Keys {
        static let rarsEnabled = "experimental.rarsEnabled"
        static let rarsOpensRar = "experimental.rarsOpensRar"
        static let defaultFormat = "pack.defaultFormat"
        static let defaultLevel = "pack.defaultLevel"
        static let advanced = "pack.advanced"
        static let developerMode = "developer.enabled"
        static let capturesNativeOutput = "developer.captureOutput"
        static let fontFaces = "developer.fontFaces"
        static let fontScales = "developer.fontScales"
    }
}
