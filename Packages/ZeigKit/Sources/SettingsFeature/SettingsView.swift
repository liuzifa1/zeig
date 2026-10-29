import ArchiveFeature
import SwiftUI
import ZeigCore
import ZeigDesign
import ZeigStore

/// The Settings sheet, opened from the gear in every tab's header.
///
/// Laid out like Filz!'s: a Form in its own NavigationStack with a close button at the top
/// right, settings first and an About section with the app's version and the Backends and About pages at the end.
public struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRars = false
    @State private var versionTaps = 0
    @State private var developerNotice = false

    public init() {}

    public var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker("Default format", selection: $settings.defaultFormat) {
                        ForEach(BackendRouter(settings: settings.routing).creatableFormats) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    Picker("Default level", selection: $settings.defaultLevel) {
                        ForEach(CompressionLevel.allCases) { Text($0.displayName).tag($0) }
                    }
                } header: {
                    Text("Creating Archives")
                } footer: {
                    Text("Preselected when you compress files. You can change them each time.")
                }

                experimentalSection

                Section("Help") {
                    NavigationLink("Format Guide") { FormatGuideView() }
                }

                if settings.developerMode {
                    DeveloperSection()
                }

                Section("About") {
                    LabeledContent("App", value: AppInfo.version)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: versionTapped)
                    NavigationLink("Backends") { BackendsView() }
                    NavigationLink("About \(AppInfo.displayName)") { AboutAppView() }
                    NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                    NavigationLink("Open Source Acknowledgements") { OpenSourceView() }
                }
            }
            .navigationTitle("Settings")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .alert("Developer mode is on", isPresented: $developerNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The Developer section is above About: the console and the Font Lab. A console button also appears next to Settings in Browse and Recent.")
            }
            .alert("Turn on the test RAR backend?", isPresented: $confirmingRars) {
                Button("Cancel", role: .cancel) {}
                Button("Turn On") { settings.rarsEnabled = true }
            } message: {
                Text("RAR archives will be created by rars, an independent open-source implementation that is still experimental. Archives it makes may not open in other apps, and it is slower than WinRAR.\n\nZeig checks every RAR it creates with 7-Zip and warns you if the check fails. Keep your original files until you've checked an archive opens where you need it.")
            }
        }
    }

    /// Seven taps on the version turn on developer mode (like HNReader).
    private func versionTapped() {
        guard !settings.developerMode else { return }
        versionTaps += 1
        if versionTaps >= 7 {
            settings.developerMode = true
            developerNotice = true
            versionTaps = 0
        }
    }

    private var experimentalSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.rarsEnabled },
                set: { on in
                    if on {
                        confirmingRars = true
                    } else {
                        settings.rarsEnabled = false
                        settings.rarsOpensRar = false
                    }
                }
            )) {
                HStack {
                    Text("Test RAR backend")
                    ExperimentalBadge()
                }
            }
            Toggle("Use it for opening RAR too", isOn: Binding(
                get: { settings.rarsOpensRar },
                set: { settings.rarsOpensRar = $0 }
            ))
            .disabled(!settings.rarsEnabled)
            NavigationLink("About creating RAR archives") {
                if let topic = GuideTopic.topic("rar-experimental") { GuideTopicView(topic: topic) }
            }
        } header: {
            Text("Experimental")
        } footer: {
            if settings.rarsEnabled {
                Label {
                    Text(settings.rarsOpensRar
                         ? "rars creates and opens RAR archives. If it can't open one, 7-Zip tries."
                         : "rars only creates RAR archives; 7-Zip, which is well tested, opens them.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
        }
    }
}
