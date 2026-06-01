import AppKit
import SwiftUI

// MARK: – Design tokens
private enum BD {
    static let bg      = Color(red: 0.000, green: 0.017, blue: 0.031)
    static let card    = Color(red: 0.016, green: 0.060, blue: 0.075)
    static let border  = Color(red: 0.058, green: 0.103, blue: 0.118)
    static let ink     = Color(red: 0.890, green: 0.914, blue: 0.921)
    static let muted   = Color(red: 0.520, green: 0.557, blue: 0.569)
    static let teal    = Color(red: 0.102, green: 0.686, blue: 0.678)
    static let danger  = Color(red: 0.840, green: 0.280, blue: 0.230)
    static let warn    = Color(red: 0.930, green: 0.680, blue: 0.200)
}

// MARK: – Button styles
private struct TealBtn: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(BD.teal.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct GhostBtn: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(BD.muted)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
    }
}

private struct NudgeBtn: ButtonStyle {  // small inline action button
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(configuration.isPressed ? BD.teal.opacity(0.6) : BD.muted)
    }
}

// MARK: – TextFieldStyle
private struct BrandField: TextFieldStyle {
    // swiftlint:disable:next identifier_name
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 12))
            .foregroundStyle(BD.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(BD.card, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(BD.border, lineWidth: 1))
    }
}

// MARK: – Row-level helpers (flat layout, no card containers)
private struct RowDivider: View {
    var body: some View { BD.border.frame(height: 1) }
}

// MARK: – Main view
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var ollamaManager = OllamaManager()

    @State private var draft: AppConfig
    @State private var selectedSection: SettingsSection = .shortcut
    @State private var devices: [AudioInputDevice] = []
    @State private var dictRows: [DictionaryRow]
    @State private var dictionaryTestInput = ""
    @State private var dictionaryTestOutput = "-"
    @State private var saveMessage = ""
    @State private var ollamaMessage = ""
    @State private var ollamaModels: [String] = []
    @State private var customToneRows: [ToneRow] = []

    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: model.config)
        _dictRows = State(initialValue: Self.rows(from: model.config.dictionary))
        _customToneRows = State(initialValue: model.config.customTones.map {
            ToneRow(id: $0.id, name: $0.name, prompt: $0.prompt)
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            brandHeader
            HStack(spacing: 0) {
                sidebar
                ZStack {
                    BD.bg
                    ScrollView {
                        sectionContent
                            .padding(.horizontal, 28)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            footer
        }
        .frame(minWidth: 720, minHeight: 560)
        .background(BD.bg)
        .environment(\.colorScheme, .dark)
        .onAppear { refreshDevices(); model.refreshPermissions() }
    }

    // MARK: Header
    private var brandHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Canvas { ctx, size in
                    var p = Path()
                    let h = size.height, w = size.width
                    p.move(to: .init(x: 0, y: h * 0.5))
                    p.addCurve(to: .init(x: w * 0.5, y: h * 0.5),
                               control1: .init(x: w * 0.15, y: h * 0.06),
                               control2: .init(x: w * 0.35, y: h * 0.94))
                    p.addCurve(to: .init(x: w, y: h * 0.5),
                               control1: .init(x: w * 0.65, y: h * 0.06),
                               control2: .init(x: w * 0.85, y: h * 0.94))
                    ctx.stroke(p, with: .color(.white),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
                .frame(width: 22, height: 12)
                Text("flowy")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .tracking(-0.2)
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(statusDotColor).frame(width: 5, height: 5)
                Text(model.status.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(.white.opacity(0.10), in: Capsule())
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(BD.teal)
    }

    // MARK: Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(SettingsSection.allCases) { section in
                let active = selectedSection == section
                Button {
                    selectedSection = section
                    if section == .audio  { refreshDevices() }
                    if section == .system { model.refreshPermissions() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(active ? BD.teal : BD.muted)
                            .frame(width: 14)
                        Text(section.title)
                            .font(.system(size: 13, weight: active ? .medium : .regular))
                            .foregroundStyle(active ? BD.ink : BD.muted)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .overlay(alignment: .leading) {
                        if active {
                            BD.teal.frame(width: 2).padding(.vertical, 6)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 10)
        .frame(width: 155)
        .background(BD.bg)
        .overlay(alignment: .trailing) { BD.border.frame(width: 1) }
    }

    // MARK: Section routing
    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .shortcut:   shortcutSection
        case .audio:      audioSection
        case .output:     outputSection
        case .dictionary: dictionarySection
        case .ai:         aiSection
        case .tone:       toneSection
        case .history:    historySection
        case .system:     systemSection
        }
    }

    // MARK: Footer
    private var footer: some View {
        HStack {
            Text(model.lastError ?? saveMessage)
                .font(.system(size: 11))
                .foregroundStyle(model.lastError == nil ? BD.muted : BD.danger)
                .lineLimit(1)
            Spacer()
            Button("Discard") { resetDraft() }.buttonStyle(GhostBtn())
            Button("Save") { saveDraft() }
                .buttonStyle(TealBtn())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(BD.bg)
        .overlay(alignment: .top) { BD.border.frame(height: 1) }
    }

    // MARK: – Sections ──────────────────────────────────────────────────────

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Shortcut")
            permissionBanners

            // Record button — slightly featured
            VStack(alignment: .leading, spacing: 8) {
                HoldRecordButton(
                    isRecording: model.status == .recording,
                    onPress: model.startRecording,
                    onRelease: model.stopRecording
                )
                .frame(maxWidth: .infinity, minHeight: 34)
                Text("Click and hold — release to transcribe.")
                    .font(.system(size: 11))
                    .foregroundStyle(BD.muted)
            }
            .padding(.bottom, 24)

            RowDivider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Global hotkey")
                        .font(.system(size: 13))
                        .foregroundStyle(BD.ink)
                    Button("reset to default") {
                        draft.hotkey = "CmdOrCtrl+Shift+Space"
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(BD.muted)
                    .buttonStyle(.plain)
                }
                Spacer()
                HotkeyRecorderView(hotkey: $draft.hotkey)
                    .frame(height: 28)
            }
            .padding(.vertical, 10)
            RowDivider()
            row("Recording limit") {
                HStack(spacing: 6) {
                    Text("\(draft.maxRecordingSecs) s")
                        .font(.system(size: 12))
                        .foregroundStyle(BD.ink)
                        .frame(width: 36, alignment: .trailing)
                    Stepper("", value: $draft.maxRecordingSecs, in: 5...300, step: 5)
                        .labelsHidden()
                }
            }
            RowDivider()
            row("Auto-stop on silence") {
                Toggle("", isOn: $draft.vadEnabled).labelsHidden().tint(BD.teal)
            }
            if draft.vadEnabled {
                RowDivider()
                row("Silence delay") {
                    HStack(spacing: 6) {
                        Text(String(format: "%.1f s", draft.vadSilenceSeconds))
                            .font(.system(size: 12))
                            .foregroundStyle(BD.ink)
                            .frame(width: 36, alignment: .trailing)
                        Stepper("", value: $draft.vadSilenceSeconds, in: 0.5...5.0, step: 0.5)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Audio")
            row("Input device") {
                HStack(spacing: 8) {
                    Picker("", selection: inputDeviceBinding) {
                        Text("System default").tag("")
                        ForEach(devices) { d in Text(d.name).tag(d.uid) }
                    }
                    .labelsHidden().frame(width: 200)
                    Button { refreshDevices() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11))
                    }
                    .buttonStyle(NudgeBtn())
                }
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Output")
            ForEach(Array(OutputMode.allCases.enumerated()), id: \.offset) { i, mode in
                Button { draft.outputMode = mode } label: {
                    HStack(alignment: .top, spacing: 11) {
                        ZStack {
                            Circle().stroke(
                                draft.outputMode == mode ? BD.teal : BD.border,
                                lineWidth: 1.5)
                                .frame(width: 15, height: 15)
                            if draft.outputMode == mode {
                                Circle().fill(BD.teal).frame(width: 7, height: 7)
                            }
                        }
                        .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mode.title)
                                .font(.system(size: 13))
                                .foregroundStyle(BD.ink)
                            Text(mode.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(BD.muted)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < OutputMode.allCases.count - 1 { RowDivider() }
            }

            // ── Translation ──────────────────────────────────────────
            RowDivider()
            translationSection
        }
    }

    @ViewBuilder
    private var translationSection: some View {
        if #available(macOS 15, *) {
            row("Translate output") {
                Toggle("", isOn: $draft.translationEnabled).labelsHidden().tint(BD.teal)
            }
            if draft.translationEnabled {
                RowDivider()
                row("Target language") {
                    Picker("", selection: $draft.translationTargetLanguage) {
                        ForEach(TranslationLanguage.supported) { lang in
                            Text(lang.name).tag(lang.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                RowDivider()
                HStack(spacing: 6) {
                    Circle().fill(BD.teal).frame(width: 5, height: 5)
                    Text("On-device · powered by Apple Translation")
                        .font(.system(size: 11))
                        .foregroundStyle(BD.muted)
                }
                .padding(.vertical, 8)
            }
        } else {
            row("Translate output") {
                Text("Requires macOS 15")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(BD.muted)
            }
        }
    }

    private var dictionarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Dictionary")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(dictRows.indices, id: \.self) { i in
                    HStack(spacing: 6) {
                        TextField("word", text: $dictRows[i].key)
                            .textFieldStyle(BrandField())
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(BD.muted)
                        TextField("replacement", text: $dictRows[i].value)
                            .textFieldStyle(BrandField())
                        Button { dictRows.remove(at: i); runDictionaryTest() } label: {
                            Image(systemName: "xmark").font(.system(size: 10))
                        }
                        .buttonStyle(NudgeBtn())
                    }
                }
                Button { dictRows.append(DictionaryRow(key: "", value: "")) } label: {
                    Label("Add", systemImage: "plus").font(.system(size: 11))
                }
                .buttonStyle(NudgeBtn())
                .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Preview")
                    .font(.system(size: 11)).foregroundStyle(BD.muted)
                TextField("Type to test substitutions…", text: $dictionaryTestInput)
                    .textFieldStyle(BrandField())
                    .onChange(of: dictionaryTestInput) { _ in runDictionaryTest() }
                Text(dictionaryTestOutput)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(BD.muted)
            }
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("AI")

            // ── Ollama status ──────────────────────────────────────────
            ollamaStatusBanner
            RowDivider()

            // ── Existing settings ──────────────────────────────────────
            row("Ollama enhancement") {
                Toggle("", isOn: $draft.ollamaEnabled).labelsHidden().tint(BD.teal)
            }
            RowDivider()
            row("Endpoint") {
                HStack(spacing: 8) {
                    TextField("http://localhost:11434", text: $draft.ollamaEndpoint)
                        .textFieldStyle(BrandField())
                        .frame(width: 200)
                    Button("Test") { Task { await checkOllama() } }
                        .buttonStyle(NudgeBtn())
                }
            }
            RowDivider()
            row("Model") {
                if !ollamaModels.isEmpty {
                    Picker("", selection: $draft.ollamaModel) {
                        ForEach(ollamaModels, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: 200)
                } else {
                    TextField("llama3.2:3b", text: $draft.ollamaModel)
                        .textFieldStyle(BrandField())
                        .frame(width: 200)
                }
            }
            if !ollamaMessage.isEmpty {
                Text(ollamaMessage)
                    .font(.system(size: 11)).foregroundStyle(BD.muted)
                    .padding(.top, 8)
            }
            RowDivider().padding(.top, 14)
            VStack(alignment: .leading, spacing: 0) {
                Text("System prompt")
                    .font(.system(size: 11)).foregroundStyle(BD.muted)
                    .padding(.top, 12).padding(.bottom, 6)
                TextEditor(text: $draft.ollamaPrompt)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(BD.ink)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 90)
                RowDivider()
            }

            // ── Recommended models ────────────────────────────────────
            recommendedModelsSection
        }
        .onAppear {
            Task { await ollamaManager.checkStatus(endpoint: draft.ollamaEndpoint) }
        }
    }

    // MARK: – Ollama status banner

    @ViewBuilder
    private var ollamaStatusBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ollamaStatusColor)
                .frame(width: 5, height: 5)
            if ollamaManager.installStatus == .checking || ollamaManager.installStatus == .installing {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 14, height: 14)
            }
            Text(ollamaStatusLabel)
                .font(.system(size: 12))
                .foregroundStyle(BD.ink)
            Spacer()
            switch ollamaManager.installStatus {
            case .notInstalled:
                Button("Install via Homebrew") {
                    Task { await ollamaManager.installOllama() }
                }
                .buttonStyle(TealBtn())
            case .stopped:
                Button("Start Ollama") {
                    ollamaManager.startServer(endpoint: draft.ollamaEndpoint)
                }
                .buttonStyle(TealBtn())
            case .running:
                Button {
                    Task { await ollamaManager.checkStatus(endpoint: draft.ollamaEndpoint) }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                }
                .buttonStyle(NudgeBtn())
            case .checking, .installing:
                EmptyView()
            }
        }
        .padding(.vertical, 10)

        if !ollamaManager.installMessage.isEmpty {
            Text(ollamaManager.installMessage)
                .font(.system(size: 11))
                .foregroundStyle(BD.muted)
                .padding(.bottom, 8)
        }
    }

    private var ollamaStatusColor: Color {
        switch ollamaManager.installStatus {
        case .running:               return BD.teal
        case .stopped, .notInstalled: return BD.danger.opacity(0.8)
        case .checking, .installing: return BD.warn
        }
    }

    private var ollamaStatusLabel: String {
        switch ollamaManager.installStatus {
        case .checking:    return "Checking…"
        case .notInstalled: return "Ollama not installed"
        case .stopped:     return "Ollama installed · server not running"
        case .running:     return "Ollama running"
        case .installing:  return "Installing Ollama…"
        }
    }

    // MARK: – Recommended models

    @ViewBuilder
    private var recommendedModelsSection: some View {
        Text("Recommended Models")
            .font(.system(size: 11))
            .foregroundStyle(BD.muted)
            .padding(.top, 16)
            .padding(.bottom, 6)

        ForEach(Array(OllamaManager.recommendedModels.enumerated()), id: \.element.id) { i, model in
            recommendedModelRow(model)
            if i < OllamaManager.recommendedModels.count - 1 { RowDivider() }
        }
    }

    @ViewBuilder
    private func recommendedModelRow(_ model: RecommendedModel) -> some View {
        let pullState   = ollamaManager.pullStates[model.name]
        let isPulling   = pullState != nil && !(pullState?.done ?? false) && pullState?.error == nil
        let isInstalled = pullState?.done == true || ollamaManager.isInstalled(model.name)

        HStack(spacing: 12) {
            // Label + tagline
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.label)
                        .font(.system(size: 13))
                        .foregroundStyle(BD.ink)
                    if model.tagline == "Recommended" {
                        Text("default")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(BD.teal)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(BD.teal.opacity(0.15), in: Capsule())
                    }
                }
                Text("\(model.tagline) · \(model.sizeLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(BD.muted)
            }

            Spacer()

            // State area
            if isPulling, let state = pullState {
                HStack(spacing: 8) {
                    if let pct = state.progress {
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(BD.border)
                                .frame(width: 80, height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(BD.teal)
                                .frame(width: 80 * pct, height: 4)
                        }
                        Text("\(Int(pct * 100))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(BD.muted)
                            .frame(width: 30, alignment: .leading)
                    } else {
                        ProgressView().scaleEffect(0.6).frame(width: 20, height: 20)
                    }
                    Button("Cancel") { ollamaManager.cancelPull(model.name) }
                        .buttonStyle(NudgeBtn())
                }
            } else if let err = pullState?.error {
                HStack(spacing: 6) {
                    Text(String(err.prefix(28)) + "…")
                        .font(.system(size: 10))
                        .foregroundStyle(BD.danger)
                    Button("Retry") {
                        ollamaManager.pullModel(model.name, endpoint: draft.ollamaEndpoint)
                    }
                    .buttonStyle(NudgeBtn())
                }
            } else if isInstalled {
                HStack(spacing: 8) {
                    Text("installed")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(BD.teal.opacity(0.75))
                    Button("Use") { draft.ollamaModel = model.name }
                        .buttonStyle(NudgeBtn())
                        .foregroundStyle(BD.teal)
                }
            } else {
                Button("Install") {
                    ollamaManager.pullModel(model.name, endpoint: draft.ollamaEndpoint)
                }
                .buttonStyle(TealBtn())
                .disabled(ollamaManager.installStatus != .running)
                .opacity(ollamaManager.installStatus == .running ? 1 : 0.4)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: – Tone section

    private var toneSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Tone")

            // Ollama warning if no endpoint configured and a non-raw tone is selected
            if draft.activeToneID != nil && draft.activeToneID != "raw" && !draft.ollamaEnabled {
                inlineBanner("Tone requires Ollama — enable it in the AI tab.",
                             action: { selectedSection = .ai }, actionLabel: "Go")
                    .padding(.bottom, 4)
            }

            // ── Built-in tones ─────────────────────────────────────
            Text("Built-in")
                .font(.system(size: 11)).foregroundStyle(BD.muted)
                .padding(.bottom, 6)

            ForEach(Array(TonePreset.builtIns.enumerated()), id: \.element.id) { i, tone in
                toneRow(tone, isBuiltIn: true)
                RowDivider()
            }

            // ── Custom tones ───────────────────────────────────────
            Text("Custom")
                .font(.system(size: 11)).foregroundStyle(BD.muted)
                .padding(.top, 16).padding(.bottom, 6)

            ForEach($customToneRows) { $row in
                customToneRow($row)
                RowDivider()
            }

            Button {
                let newID = UUID().uuidString
                customToneRows.append(ToneRow(id: newID, name: "", prompt: ""))
            } label: {
                Label("New Tone", systemImage: "plus").font(.system(size: 11))
            }
            .buttonStyle(NudgeBtn())
            .padding(.top, 8)
        }
    }

    private func toneRow(_ tone: TonePreset, isBuiltIn: Bool) -> some View {
        let selected = draft.activeToneID == tone.id
        return Button {
            draft.activeToneID = selected ? nil : tone.id
        } label: {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    Circle()
                        .stroke(selected ? BD.teal : BD.border, lineWidth: 1.5)
                        .frame(width: 15, height: 15)
                    if selected { Circle().fill(BD.teal).frame(width: 7, height: 7) }
                }
                .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tone.name)
                            .font(.system(size: 13))
                            .foregroundStyle(BD.ink)
                        if tone.id == "clean" {
                            Text("default")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(BD.teal)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(BD.teal.opacity(0.15), in: Capsule())
                        }
                        if tone.id == "raw" {
                            Text("no AI")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(BD.muted)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(BD.border, in: Capsule())
                        }
                    }
                    Text(toneSubtitle(tone))
                        .font(.system(size: 11))
                        .foregroundStyle(BD.muted)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func customToneRow(_ row: Binding<ToneRow>) -> some View {
        let isSelected = draft.activeToneID == row.id
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Button {
                    draft.activeToneID = isSelected ? nil : row.id
                } label: {
                    ZStack {
                        Circle()
                            .stroke(isSelected ? BD.teal : BD.border, lineWidth: 1.5)
                            .frame(width: 15, height: 15)
                        if isSelected { Circle().fill(BD.teal).frame(width: 7, height: 7) }
                    }
                }
                .buttonStyle(.plain)
                TextField("Tone name", text: row.name)
                    .textFieldStyle(BrandField())
                    .frame(maxWidth: 160)
                Spacer()
                Button {
                    if draft.activeToneID == row.id { draft.activeToneID = nil }
                    customToneRows.removeAll { $0.id == row.id }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                }
                .buttonStyle(NudgeBtn())
            }
            .padding(.vertical, 8)

            TextEditor(text: row.prompt)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(BD.ink)
                .scrollContentBackground(.hidden)
                .background(BD.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(BD.border, lineWidth: 1)
                )
                .frame(minHeight: 70)
                .padding(.bottom, 8)
        }
    }

    private func toneSubtitle(_ tone: TonePreset) -> String {
        switch tone.id {
        case "raw":      return "Output the raw transcription unchanged"
        case "clean":    return "Fix grammar, punctuation, and self-corrections"
        case "formal":   return "Rewrite in formal professional English"
        case "business": return "Rewrite in business casual — clear and workplace-ready"
        case "concise":  return "Trim to essentials, remove filler"
        case "bullets":  return "Convert to bullet points"
        default:         return "Custom tone"
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionTitle("History")
                Spacer()
                Button { model.clearHistory() } label: {
                    Text("Clear").font(.system(size: 12))
                }
                .buttonStyle(NudgeBtn())
                .disabled(model.history.isEmpty)
            }
            if model.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 28)).foregroundStyle(BD.border)
                    Text("No transcriptions yet")
                        .font(.system(size: 13)).foregroundStyle(BD.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.history.enumerated()), id: \.offset) { _, text in
                        HStack(alignment: .top, spacing: 10) {
                            Text(text)
                                .font(.system(size: 12)).foregroundStyle(BD.ink)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button { TextOutput.copyToClipboard(text) } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11)).foregroundStyle(BD.muted)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 9)
                        .background(BD.card)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("System")
            row("Launch at login") {
                Toggle("", isOn: $draft.autostart).labelsHidden().tint(BD.teal)
            }
            RowDivider()

            // Permission rows
            permRow("Speech Recognition", granted: model.permissions.speechAuthorized)
            RowDivider()
            permRow("Microphone",         granted: model.permissions.microphoneAuthorized)
            RowDivider()
            permRow("Accessibility",       granted: model.permissions.accessibilityTrusted)
            RowDivider()
            Button {
                TextOutput.requestAccessibilityAccess()
                TextOutput.openAccessibilitySettings()
            } label: {
                Label("Open Accessibility Settings", systemImage: "lock.open")
                    .font(.system(size: 12))
            }
            .buttonStyle(NudgeBtn())
            .padding(.vertical, 10)
            RowDivider()

            // Config path
            row("Config") {
                HStack(spacing: 8) {
                    Text(model.configPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(BD.muted)
                        .textSelection(.enabled)
                        .lineLimit(1)
                    Button {
                        NSWorkspace.shared.selectFile(
                            AppConfig.configURL.path, inFileViewerRootedAtPath: "")
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(NudgeBtn())
                }
            }
        }
    }

    // MARK: – Permission banners (minimal inline banners)
    @ViewBuilder
    private var permissionBanners: some View {
        if !model.permissions.accessibilityTrusted {
            inlineBanner(
                "Accessibility required — if Flowy is already listed in System Settings, remove and re-add it.",
                action: { TextOutput.requestAccessibilityAccess(); TextOutput.openAccessibilitySettings() },
                actionLabel: "Fix"
            )
        }
        if !model.permissions.speechAuthorized {
            inlineBanner(
                "Speech Recognition not authorized.",
                action: model.requestInitialPermissions,
                actionLabel: "Request"
            )
        }
        if !model.permissions.microphoneAuthorized {
            inlineBanner(
                "Microphone access required.",
                action: model.requestInitialPermissions,
                actionLabel: "Request"
            )
        }
    }

    // MARK: – Shared sub-views
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(BD.ink)
            .padding(.bottom, 16)
    }

    private func row<C: View>(_ label: String, @ViewBuilder control: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(BD.ink)
            Spacer()
            control()
        }
        .padding(.vertical, 10)
    }

    private func permRow(_ title: String, granted: Bool) -> some View {
        HStack {
            Circle()
                .fill(granted ? BD.teal : BD.danger.opacity(0.8))
                .frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(BD.ink)
            Spacer()
            Text(granted ? "granted" : "missing")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(granted ? BD.teal.opacity(0.75) : BD.danger.opacity(0.75))
        }
        .padding(.vertical, 10)
    }

    private func inlineBanner(
        _ message: String,
        action: @escaping () -> Void,
        actionLabel: String
    ) -> some View {
        HStack(spacing: 10) {
            Circle().fill(BD.warn).frame(width: 5, height: 5)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(BD.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(actionLabel, action: action)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BD.warn)
                .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.bottom, 6)
    }

    // MARK: – Bindings & logic
    private var inputDeviceBinding: Binding<String> {
        Binding(
            get: { draft.inputDevice ?? "" },
            set: { draft.inputDevice = $0.isEmpty ? nil : $0 }
        )
    }

    private var statusDotColor: Color {
        switch model.status {
        case .idle:         return .white.opacity(0.4)
        case .recording:    return Color(red: 1.0, green: 0.42, blue: 0.38)
        case .transcribing: return .white
        }
    }

    private func refreshDevices() { devices = AudioDeviceManager.inputDevices() }

    private func saveDraft() {
        var clean = draft
        clean.dictionary = collectedDictionary()
        clean.customTones = customToneRows
            .map { TonePreset(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                              prompt: $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.name.isEmpty }
        do {
            try model.saveConfig(clean)
            resetDraft()
            saveMessage = "Saved"
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    private func resetDraft() {
        draft = model.config
        dictRows = Self.rows(from: model.config.dictionary)
        customToneRows = model.config.customTones.map {
            ToneRow(id: $0.id, name: $0.name, prompt: $0.prompt)
        }
        runDictionaryTest()
    }

    private func collectedDictionary() -> [String: String] {
        var r: [String: String] = [:]
        for row in dictRows {
            let k = row.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let v = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !k.isEmpty { r[k] = v }
        }
        return r
    }

    private func runDictionaryTest() {
        guard !dictionaryTestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            dictionaryTestOutput = "-"; return
        }
        dictionaryTestOutput = DictionaryRewriter.apply(
            dictionaryTestInput, dictionary: collectedDictionary())
    }

    private func checkOllama() async {
        ollamaMessage = "Checking…"
        let result = await OllamaClient.status(endpoint: draft.ollamaEndpoint)
        if result.reachable {
            ollamaModels = result.models
            if draft.ollamaModel.isEmpty, let first = result.models.first {
                draft.ollamaModel = first
            }
            ollamaMessage = "Connected · \(result.models.count) model\(result.models.count == 1 ? "" : "s") found."
        } else {
            ollamaModels = []
            ollamaMessage = result.error ?? "Could not reach Ollama."
        }
    }

    private static func rows(from dict: [String: String]) -> [DictionaryRow] {
        dict.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { DictionaryRow(key: $0.key, value: $0.value) }
    }
}

// MARK: – Section enum
private enum SettingsSection: String, CaseIterable, Identifiable {
    case shortcut, audio, output, dictionary, ai, tone, history, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortcut:   "Shortcut"
        case .audio:      "Audio"
        case .output:     "Output"
        case .dictionary: "Dictionary"
        case .ai:         "AI"
        case .tone:       "Tone"
        case .history:    "History"
        case .system:     "System"
        }
    }

    var symbol: String {
        switch self {
        case .shortcut:   "keyboard"
        case .audio:      "waveform"
        case .output:     "text.cursor"
        case .dictionary: "book"
        case .ai:         "sparkles"
        case .tone:       "wand.and.sparkles"
        case .history:    "clock.arrow.circlepath"
        case .system:     "gearshape"
        }
    }
}

// MARK: – DictionaryRow
private struct DictionaryRow: Identifiable, Equatable {
    let id = UUID()
    var key:   String
    var value: String
}

// MARK: – ToneRow
private struct ToneRow: Identifiable {
    let id: String   // used as TonePreset.id
    var name: String
    var prompt: String
}
