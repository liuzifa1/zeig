import SwiftUI
import ZeigBackends
import ZeigCore
import ZeigDesign
import ZeigStore

/// The create sheet: name, format, level, password, and the format's advanced settings, each
/// with a one-line explanation and an ⓘ for the full one.
struct PackSheet: View {
    let sources: PackSources
    /// Called after the archive was written (the folder leaves selection mode).
    let onCreated: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(FileLibrary.self) private var library
    @Environment(RecentStore.self) private var recent
    @Environment(\.dismiss) private var dismiss

    @State private var format: ArchiveFormat = .zip
    @State private var level: CompressionLevel = .normal
    @State private var stem = ""
    @State private var password = ""
    @State private var showsPassword = false
    @State private var advanced: [String: String] = [:]
    @State private var showsAdvanced = false
    @State private var guide: GuideTopic?
    @State private var actions = ArchiveActions()
    @State private var verificationFailure: String?
    @State private var loaded = false
    @Environment(\.fontTheme) private var fonts

    private var router: BackendRouter { BackendRouter(settings: settings.routing) }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                formatSection
                Section("Compression") {
                    Picker("Level", selection: $level) {
                        ForEach(CompressionLevel.allCases) { Text($0.displayName).tag($0) }
                    }
                    explanation(
                        level == .store ? "Copies files as they are. Best for photos and videos." : "Higher levels are smaller but slower.",
                        topic: "compression-level"
                    )
                }
                if format.supportsPassword { passwordSection }
                if !FormatOptions.options(for: format).isEmpty { advancedSection }
            }
            .navigationTitle("New Archive")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(!canCreate)
                }
            }
            .sheet(item: $guide) { topic in
                NavigationStack {
                    GuideTopicView(topic: topic)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { guide = nil } } }
                }
            }
            .alert("7-Zip couldn't read the archive back", isPresented: Binding(get: { verificationFailure != nil }, set: { if !$0 { verificationFailure = nil } })) {
                Button("OK", role: .cancel) { finish() }
            } message: {
                Text("The RAR archive was made by the experimental backend, and the check with 7-Zip failed, so other apps may not open it. It has been kept so you can try it; your original files weren't changed.\n\n\(verificationFailure ?? "")")
            }
            .archiveActions(actions)
            .interactiveDismissDisabled(actions.operation.isRunning)
        }
        .onAppear(perform: loadDefaults)
        .onChange(of: format) { _, new in advanced = settings.advanced(for: new) }
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            HStack(spacing: 2) {
                TextField("Name", text: $stem)
                    .autocorrectionDisabled()
                Text("." + format.fileExtension)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(sources.urls.count == 1 ? "From “\(sources.urls[0].lastPathComponent)”." : "From \(sources.urls.count) items.")
        }
    }

    private var formatSection: some View {
        Section("Format") {
            Picker("Format", selection: $format) {
                Section("Common") {
                    ForEach(ArchiveFormat.common) { Text($0.displayName).tag($0) }
                }
                Section("More formats") {
                    ForEach(router.creatableFormats.filter { !ArchiveFormat.common.contains($0) }) { format in
                        Text(format == .rar ? "RAR (experimental)" : format.displayName).tag(format)
                    }
                }
            }
            if format == .rar {
                Label {
                    Text("RAR archives are made by rars, an experimental open-source implementation. Keep your originals until you've checked the archive opens where you need it.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.footnote)
                explanation("Zeig checks every RAR it makes with 7-Zip.", topic: "rar-experimental")
            } else if format.isSingleFile {
                explanation(
                    singleFileProblem ?? "Compresses one file, without folders.",
                    topic: "single-file",
                    warning: singleFileProblem != nil
                )
            } else {
                explanation(formatSummary, topic: "choosing-format")
            }
        }
    }

    private var passwordSection: some View {
        Section {
            HStack {
                Group {
                    if showsPassword {
                        TextField("Password (optional)", text: $password)
                    } else {
                        SecureField("Password (optional)", text: $password)
                    }
                }
                .textContentType(.newPassword)
                .autocorrectionDisabled()
                Button(showsPassword ? "Hide" : "Show") { showsPassword.toggle() }
                    .buttonStyle(.borderless)
            }
        } header: {
            Text("Password")
        } footer: {
            Text("Zeig doesn't keep the password. If it's forgotten, the files can't be recovered.")
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced settings", isExpanded: $showsAdvanced) {
                ForEach(FormatOptions.options(for: format)) { option in
                    optionRow(option)
                }
            }
        } footer: {
            Text("Most people never change these.")
        }
    }

    @ViewBuilder
    private func optionRow(_ option: FormatOption) -> some View {
        let binding = Binding(get: { advanced[option.id] ?? option.defaultValue }, set: { advanced[option.id] = $0 })
        let disabled = option.needsPassword && password.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            Group {
                switch option.kind {
                case .choice(let choices):
                    Picker(option.title, selection: binding) {
                        ForEach(choices) { Text($0.label).tag($0.value) }
                    }
                case .toggle:
                    Toggle(option.title, isOn: Binding(get: { binding.wrappedValue == "on" }, set: { binding.wrappedValue = $0 ? "on" : "off" }))
                case .text(let placeholder):
                    LabeledContent(option.title) {
                        TextField(placeholder, text: binding)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            // Only the control: the explanation and its ⓘ stay usable.
            .disabled(disabled)
            explanation(disabled ? "Needs a password. " + option.summary : option.summary, topic: option.guide)
        }
    }

    /// A short explanation with an ⓘ that opens the guide topic.
    private func explanation(_ text: String, topic: GuideTopic.ID, warning: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(fonts.font(.guide))
                .foregroundStyle(warning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            Spacer(minLength: 4)
            Button {
                guide = GuideTopic.topic(topic)
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("More about this")
        }
    }

    // MARK: Logic

    private var formatSummary: String {
        switch format {
        case .zip: "Opens everywhere, no extra app needed."
        case .sevenZip: "Smaller than ZIP; needs 7-Zip or a similar app to open."
        case .tarGzip, .tarXz, .tarBzip2, .tarZstd, .tarLz4: "The usual format on Mac and Linux. Can't be encrypted."
        case .tar: "Packs files without compressing them."
        case .iso: "A disc image that computers can mount like a drive."
        default: "Opens in most archive apps."
        }
    }

    private var singleFileProblem: String? {
        let isFolder = sources.urls.first.map { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } ?? false
        guard sources.urls.count != 1 || isFolder else { return nil }
        let tarVersion = ArchiveFormat.allCases.first { FormatDetector.compressor(of: $0) == format }
        return "\(format.displayName) holds exactly one file." + (tarVersion.map { " For folders, use \($0.displayName)." } ?? "")
    }

    private var canCreate: Bool {
        !stem.trimmingCharacters(in: .whitespaces).isEmpty && !actions.operation.isRunning
            && !(format.isSingleFile && singleFileProblem != nil)
    }

    private func loadDefaults() {
        guard !loaded else { return }
        loaded = true
        format = router.creator(for: settings.defaultFormat) != nil ? settings.defaultFormat : .zip
        level = settings.defaultLevel
        advanced = settings.advanced(for: format)
        stem = FileNaming.split(FileNaming.archiveName(for: sources.urls, format: .zip)).stem
    }

    private func create() async {
        let name = stem.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        let destination = FileNaming.unique(sources.folder.appendingPathComponent(name + "." + format.fileExtension))
        let request = PackRequest(
            destination: destination, sources: sources.urls, format: format, level: level,
            password: password, advanced: advanced
        )
        let service = ArchiveService(settings: settings.routing)
        do {
            let result = try await actions.operation.run("Creating \(destination.lastPathComponent)…") { (progress) throws(ArchiveError) in
                try await service.create(request, progress: progress)
            }
            settings.remember(advanced, for: format)
            library.noteChange()
            if let first = result.files.first { recent.record(library.relativePath(of: first), .created) }
            if case .failed(let error) = result.verification {
                verificationFailure = error.detail ?? error.message
            } else {
                finish()
            }
        } catch .cancelled {
        } catch {
            actions.alert = AlertContent("Can't create the archive", error)
        }
    }

    private func finish() {
        onCreated()
        dismiss()
    }
}
