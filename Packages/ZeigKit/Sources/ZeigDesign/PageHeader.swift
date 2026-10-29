// From HNReader's HNDesign (same author), unchanged: Zeig shares its header and glass look.
// The `hn` prefix is kept so code reads the same in both projects.

import SwiftUI

/// A Photos-style header for a tab's root screen: a large title with a small line under it
/// (a date, a status), and glass controls on the title's row.
///
/// It stays pinned while the content scrolls under it, behind the system's *soft* (progressive)
/// scroll-edge blur on iOS 26+ (a fading material before), so the top of the screen turns
/// gradually transparent instead of ending in a hard bar edge. iOS 27 defaults to the hard
/// style, which draws a dividing line; `pageHeader` asks for soft explicitly. Attach it with
/// `.pageHeader { … }`.
///
/// Controls are `pageHeaderControlSize` (44 pt) tall: round icon buttons (`PageHeaderIcon`)
/// or capsules, made glass with `pageHeaderControl(in:)`. `leading` sits before the title
/// (a back button on pushed screens).
public struct PageHeader<Leading: View, Title: View, Subtitle: View, Controls: View>: View {
    private let leading: Leading
    private let title: Title
    private let subtitle: Subtitle
    private let controls: Controls

    public init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder title: () -> Title,
        @ViewBuilder subtitle: () -> Subtitle,
        @ViewBuilder controls: () -> Controls
    ) {
        self.leading = leading()
        self.title = title()
        self.subtitle = subtitle()
        self.controls = controls()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                leading
                title
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                HStack(spacing: 10) { controls }
                    .hnGlassContainer(spacing: 10)
            }
            subtitle
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                // Under the title, not under the back button.
                .padding(.leading, Leading.self == EmptyView.self ? 0 : pageHeaderControlSize + 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}

public extension PageHeader where Leading == EmptyView {
    init(
        @ViewBuilder title: () -> Title,
        @ViewBuilder subtitle: () -> Subtitle,
        @ViewBuilder controls: () -> Controls
    ) {
        self.init(leading: { EmptyView() }, title: title, subtitle: subtitle, controls: controls)
    }
}

/// A round glass back button for screens that hide the navigation bar (`PageHeader`'s
/// `leading`, the story sheet).
public struct BackButton: View {
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            PageHeaderIcon("chevron.backward")
        }
        .pageHeaderControl(in: Circle())
        .accessibilityLabel("Back")
    }
}

/// Height of every `PageHeader` control, and the diameter of round ones.
public let pageHeaderControlSize: CGFloat = 44

/// An icon for a round `PageHeader` control. Give the button an `accessibilityLabel`.
public struct PageHeaderIcon: View {
    private let systemImage: String

    public init(_ systemImage: String) {
        self.systemImage = systemImage
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: pageHeaderControlSize, height: pageHeaderControlSize)
            .contentShape(Circle())
    }
}

public extension View {
    /// Pins `header` (normally a `PageHeader`) to the top of a tab's root screen and hides the
    /// navigation bar there; pushed screens bring their own bar. No-op on macOS, which keeps
    /// its window toolbar.
    func pageHeader(@ViewBuilder _ header: () -> some View) -> some View {
        modifier(PageHeaderPlacement(header: header(), hidesNavigationBar: true))
    }

    /// Pins `content` to the top of the scrolling content (under the navigation bar if there
    /// is one: a switch, a filter row, a sheet's own top bar), with the same soft scroll-edge
    /// treatment as `pageHeader`. Leaves the navigation bar alone. Works on macOS too.
    func pinnedTopBar(@ViewBuilder _ content: () -> some View) -> some View {
        modifier(PageHeaderPlacement(header: content(), hidesNavigationBar: false))
    }

    /// The soft (progressive) scroll-edge blur at the top on 26+, instead of iOS 27's hard
    /// default with its dividing line. For scroll views under the system navigation bar.
    @ViewBuilder
    func softTopScrollEdge() -> some View {
        if #available(iOS 26, macOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    /// Styles a `Button` or `Menu` as a `PageHeader` control: interactive glass in `shape`.
    func pageHeaderControl<S: Shape>(in shape: S) -> some View {
        buttonStyle(.plain)
            .hnGlass(in: shape, interactive: true)
    }
}

private struct PageHeaderPlacement<Header: View>: ViewModifier {
    let header: Header
    let hidesNavigationBar: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        if hidesNavigationBar {
            pinned(content)
                .toolbar(.hidden, for: .navigationBar)
        } else {
            pinned(content)
        }
        #else
        if hidesNavigationBar {
            content
        } else {
            pinned(content)
        }
        #endif
    }

    @ViewBuilder
    private func pinned(_ content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            // A safe-area bar gets the system scroll-edge effect under it.
            content
                .scrollEdgeEffectStyle(.soft, for: .top)
                .safeAreaBar(edge: .top, spacing: 0) { header }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) {
                header.background { FadingBarBackground() }
            }
        }
    }
}

/// Pre-26 stand-in for the scroll-edge blur: bar material that fades out below the header.
private struct FadingBarBackground: View {
    var body: some View {
        Rectangle()
            .fill(.bar)
            .mask(LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                startPoint: .top,
                endPoint: .bottom
            ))
            .padding(.bottom, -16)
            .ignoresSafeArea(edges: .top)
    }
}
