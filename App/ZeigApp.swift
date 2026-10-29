import SwiftUI
import ZeigDesign
import ZeigStore

/// Creates the shared objects and hands them to every screen through the environment.
@main
struct ZeigApp: App {
    @State private var settings = AppSettings()
    @State private var library = FileLibrary.documents()
    @State private var recent = RecentStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                // At the root so sheets get it too (a sheet inherits the environment of the
                // view it's attached to, not of views inside that).
                .environment(\.fontTheme, FontTheme(faceIDs: settings.fontFaceIDs, scales: settings.fontScales))
                .environment(settings)
                .environment(library)
                .environment(recent)
        }
    }
}
