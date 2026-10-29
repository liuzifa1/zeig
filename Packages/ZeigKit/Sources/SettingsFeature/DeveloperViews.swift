import SwiftUI
import ZeigCore
import ZeigDesign
import ZeigStore

/// Settings → Developer (tap the App version seven times): the console (full sheet, and the
/// picture-in-picture window), the log's export, capturing native output, the Font Lab, and
/// turning developer mode off again.
struct DeveloperSection: View {
    @Environment(AppSettings.self) private var settings
    @State private var showsConsole = false
    @State private var isExporting = false

    var body: some View {
        @Bindable var settings = settings
        Section {
            Button("Open Console") { showsConsole = true }
            #if os(iOS)
            if ConsolePictureInPicture.isSupported {
                Toggle("Picture in picture", isOn: Binding(
                    get: { ConsolePictureInPicture.shared.isActive },
                    set: { $0 ? ConsolePictureInPicture.shared.start() : ConsolePictureInPicture.shared.stop() }
                ))
            }
            #endif
            Toggle("Capture native output", isOn: $settings.capturesNativeOutput)
            NavigationLink("Font Lab") { FontLabView() }
        } header: {
            Text("Developer")
        } footer: {
            Text("The console logs what the engines do: routing, timings, errors. Picture in picture shows its latest lines in a floating window that stays over other apps too. Capture native output adds anything the C, C++ and Rust code prints.")
        }
        Section {
            Button("Export Log…") { isExporting = true }
            ShareLink(item: ZeigLog.export()) { Text("Share Log") }
            Button("Clear Log", role: .destructive) { ZeigLog.clear() }
            Button("Turn Off Developer Mode", role: .destructive) {
                #if os(iOS)
                ConsolePictureInPicture.shared.stop()
                #endif
                settings.capturesNativeOutput = false
                settings.developerMode = false
            }
        }
        .sheet(isPresented: $showsConsole) { ConsoleView() }
        .logExporter(isPresented: $isExporting)
    }
}

/// Developer → Font Lab: a face and a size for each kind of text, with a live preview.
/// Changes apply to the whole app at once.
struct FontLabView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.fontTheme) private var fonts

    var body: some View {
        Form {
            Section("Preview") {
                FontPreview()
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
            ForEach(FontRole.allCases) { role in
                Section {
                    NavigationLink {
                        FontPicker(role: role)
                    } label: {
                        LabeledContent("Font", value: fonts.face(role).name)
                    }
                    VStack(alignment: .leading) {
                        LabeledContent("Size", value: fonts.scale(role).formatted(.percent.precision(.fractionLength(0))))
                        Slider(value: scaleBinding(role), in: 0.7...1.5, step: 0.05)
                    }
                } header: {
                    Text(role.name)
                } footer: {
                    Text(role.explanation)
                }
            }
            Section {
                Button("Reset All Fonts") {
                    settings.fontFaceIDs = [:]
                    settings.fontScales = [:]
                }
                .disabled(settings.fontFaceIDs.isEmpty && settings.fontScales.isEmpty)
            }
        }
        .navigationTitle("Font Lab")
        .inlineNavigationTitle()
    }

    private func scaleBinding(_ role: FontRole) -> Binding<Double> {
        Binding(
            get: { settings.fontScales[role.rawValue] ?? 1 },
            set: { settings.fontScales[role.rawValue] = abs($0 - 1) < 0.001 ? nil : $0 }
        )
    }
}

/// A miniature Browse screen and a guide paragraph in the current fonts.
private struct FontPreview: View {
    @Environment(\.fontTheme) private var fonts

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Browse").font(fonts.font(.title))
                Text("12 items · 48 MB").font(fonts.font(.subtitle, .subheadline)).foregroundStyle(.secondary)
            }
            ForEach([("Holiday Photos", "folder.fill", "Oct 27, 2026"), ("backup.tar.xz", "doc.zipper", "1.2 GB · Oct 26, 2026")], id: \.0) { name, symbol, detail in
                HStack(spacing: 12) {
                    Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(fonts.font(.fileName))
                        Text(detail).font(fonts.font(.subtitle)).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Text("All Files (3)").font(fonts.font(.indicator))
                ExperimentalBadge()
            }
            Text("A solid archive compresses all files as one stream: smaller for many similar files, but slower to open one file.")
                .font(fonts.font(.guide))
                .foregroundStyle(.secondary)
        }
    }
}

/// Every face for one role: the built-in ones, then each installed family, searchable.
private struct FontPicker: View {
    let role: FontRole
    @Environment(AppSettings.self) private var settings
    @Environment(\.fontTheme) private var fonts
    @State private var query = ""

    var body: some View {
        let families = FontFace.installedFamilies.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        List {
            Section("Built in") {
                ForEach(FontFace.builtIn) { row($0) }
            }
            Section("Installed (\(families.count))") {
                ForEach(families, id: \.self) { row(.installed(family: $0)) }
            }
        }
        .searchable(text: $query, prompt: "Font families")
        .navigationTitle(role.name)
        .inlineNavigationTitle()
    }

    private func row(_ face: FontFace) -> some View {
        Button {
            settings.fontFaceIDs[role.rawValue] = face == .system ? nil : face.id
        } label: {
            HStack {
                Text(face.name)
                    .font(face.font(role.defaultStyle == .largeTitle ? .title2 : .body, weight: role.defaultWeight))
                    .foregroundStyle(.primary)
                Spacer()
                if fonts.face(role) == face {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
