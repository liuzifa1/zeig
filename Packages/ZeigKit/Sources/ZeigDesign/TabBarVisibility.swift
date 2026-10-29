import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public extension View {
    /// Hides the tab bar while `hidden` is true, so a bottom toolbar can take its place (the
    /// selection toolbar, like Files). The tab bar comes back when the screen goes away.
    ///
    /// Through UIKit (`setTabBarHidden`), not SwiftUI's `.toolbar(.hidden, for: .tabBar)`: on
    /// the Search tab (iOS 26+) the SwiftUI modifier makes the system end the search and move
    /// its field into the navigation bar for good (found in HNReader). No-op on macOS.
    func hidesTabBar(_ hidden: Bool) -> some View {
        #if os(iOS)
        background { TabBarHider(hidden: hidden) }
        #else
        self
        #endif
    }
}

#if os(iOS)
/// Finds the enclosing `UITabBarController` (public API) and shows or hides its bar.
private struct TabBarHider: UIViewControllerRepresentable {
    var hidden: Bool

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        guard controller.hidden != hidden else { return }
        controller.hidden = hidden
        controller.apply(animated: true)
    }

    final class Controller: UIViewController {
        var hidden = false

        func apply(animated: Bool) {
            // Only the screen on top owns the bar: a screen pushed over this one keeps its own.
            guard let tabs = tabBarController, isOnTop, tabs.isTabBarHidden != hidden else { return }
            tabs.setTabBarHidden(hidden, animated: animated)
        }

        private var isOnTop: Bool {
            guard let navigation = navigationController else { return true }
            var current: UIViewController? = self
            while let controller = current {
                if controller === navigation.topViewController { return true }
                current = controller.parent
            }
            return false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply(animated: animated)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if hidden, let tabs = tabBarController, tabs.isTabBarHidden {
                tabs.setTabBarHidden(false, animated: animated)
            }
        }
    }
}
#endif
