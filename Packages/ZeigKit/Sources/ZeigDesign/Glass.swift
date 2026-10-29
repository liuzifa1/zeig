// From HNReader's HNDesign (same author), unchanged: Zeig shares its header and glass look.
// The `hn` prefix is kept so code reads the same in both projects.

import SwiftUI

// Liquid Glass with graceful fallbacks.
//
// System chrome (tab bars, toolbars, sheets, menus) adopts Liquid Glass automatically on
// iOS/macOS 26 when built with the current SDK. These helpers are only for the app's own
// floating controls — the reading bar, the Read pill, round action buttons. On 26+ they
// use `glassEffect` / `.glass` button styles; on iOS 18 / macOS 15 they fall back to
// materials that read the same way.

public extension View {
    /// A Liquid Glass background in `shape` (material on older systems).
    @ViewBuilder
    func hnGlass<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(Self.glass(interactive: interactive, tint: tint), in: shape)
        } else {
            self
                .background(tint.map { AnyShapeStyle($0.opacity(0.85)) } ?? AnyShapeStyle(.regularMaterial), in: shape)
                .overlay(shape.stroke(.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
    }

    /// Groups nearby glass elements so they blend and morph together on 26+.
    @ViewBuilder
    func hnGlassContainer(spacing: CGFloat? = nil) -> some View {
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    @available(iOS 26, macOS 26, *)
    private static func glass(interactive: Bool, tint: Color?) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

public extension View {
    /// Floating-control button style for `Button` and `Menu`: `.glass` / `.glassProminent`
    /// on 26+, a material (or accent-filled) capsule before. Combine with
    /// `.buttonBorderShape(.circle)` for round buttons.
    @ViewBuilder
    func hnGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26, macOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.buttonStyle(FallbackGlassButtonStyle(prominent: prominent))
        }
    }
}

/// Pre-26 look for `hnGlassButtonStyle`.
private struct FallbackGlassButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
            .background(
                prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.regularMaterial),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
