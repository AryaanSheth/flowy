import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    @State private var draft: AppConfig
    @State private var selectedSection: SettingsSection = .shortcut
    @State private var devices: [AudioInputDevice] = []
    @State private var dictRows: [DictionaryRow]
    @State private var dictionaryTestInput = ""
    @State private var dictionaryTestOutput = "-"
    @State private var saveMessage = ""
    @State private var ollamaMessage = ""
    @State private var ollamaModels: [String] = []

    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: model.config)
        _dictRows = State(initialValue: Self.rows(from: model.config.dictionary))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                ScrollView {
                    sectionContent
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 640)
        .onAppear {
            refreshDevices()
            model.refreshPermissions()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("flowy")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("local dictation for macOS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(model.status.label, systemImage: model.status.systemImageName)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.16), in: Capsule())
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                    if section == .audio { refreshDevices() }
                    if section == .system { model.refreshPermissions() }
                } label: {
                    Label(section.title, systemImage: section.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            selectedSection == section
                                ? Color.accentColor.opacity(0.14)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(14)
        .frame(width: 172)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .shortcut: shortcutSection
        case .audio: audioSection
        case .output: outputSection
        case .dictionary: dictionarySection
        case .ai: aiSection
        case .history: historySection
        case .system: systemSection
        }
    }

    private var footer: some View {
        HStack {
            Text(model.lastError ?? saveMessage)
                .font(.caption)
                .foregroundStyle(model.lastError == nil ? Color.secondary : Color.red)
                .lineLimit(1)
            Spacer()
            Button("Discard") {
                resetDraft()
            }
            Button("Save") {
                saveDraft()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Shortcut")
            permissionBanners

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HoldRecordButton(
                        isRecording: model.status == .recording,
                        onPress: model.startRecording,
                        onRelease: model.stopRecording
                    )
                    .frame(width: 210, height: 44)

                    Text("Click and hold, then release to transcribe.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            GroupBox("Global hotkey") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HotkeyRecorderView(hotkey: $draft.hotkey)
                            .frame(width: 250, height: 32)
                        Button {
                            draft.hotkey = "CmdOrCtrl+Shift+Space"
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                    }
                    Text("Click the shortcut field, then press the macro or key combination. Save to activate it.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            GroupBox("Recording limit") {
                Stepper(value: $draft.maxRecordingSecs, in: 5...300, step: 5) {
                    Text("\(draft.maxRecordingSecs) seconds")
                }
            }
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Audio")
            GroupBox("Input device") {
                HStack {
                    Picker("Microphone", selection: inputDeviceBinding) {
                        Text("System default").tag("")
                        ForEach(devices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Button {
                        refreshDevices()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Output")
            GroupBox("Text delivery") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(OutputMode.allCases) { mode in
                        Button {
                            draft.outputMode = mode
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: draft.outputMode == mode ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.title)
                                        .fontWeight(.medium)
                                    Text(mode.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var dictionarySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Dictionary")
            GroupBox("Word substitutions") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(dictRows.indices, id: \.self) { index in
                        HStack {
                            TextField("word", text: $dictRows[index].key)
                                .textFieldStyle(.roundedBorder)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            TextField("replacement", text: $dictRows[index].value)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                dictRows.remove(at: index)
                                runDictionaryTest()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    Button {
                        dictRows.append(DictionaryRow(key: "", value: ""))
                    } label: {
                        Label("Add substitution", systemImage: "plus")
                    }
                }
            }

            GroupBox("Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Type text to preview substitutions", text: $dictionaryTestInput)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: dictionaryTestInput) { _ in runDictionaryTest() }
                    Text(dictionaryTestOutput)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("AI")

            GroupBox("Ollama enhancement") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable local cleanup pass", isOn: $draft.ollamaEnabled)
                    Text("This runs after every dictation and can add noticeable delay, especially with 7B+ models.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("http://localhost:11434", text: $draft.ollamaEndpoint)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            Task { await checkOllama() }
                        } label: {
                            Label("Test", systemImage: "bolt.horizontal.circle")
                        }
                    }

                    if !ollamaModels.isEmpty {
                        Picker("Model", selection: $draft.ollamaModel) {
                            ForEach(ollamaModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    } else {
                        TextField("Model", text: $draft.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                    }

                    Text(ollamaMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $draft.ollamaPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor))
                        )
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                sectionTitle("History")
                Spacer()
                Button {
                    model.clearHistory()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(model.history.isEmpty)
            }

            if model.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("No transcriptions yet")
                        .font(.headline)
                    Text("Hold the hotkey or the record button and speak.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(model.history.enumerated()), id: \.offset) { _, text in
                        HStack(alignment: .top) {
                            Text(text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                TextOutput.copyToClipboard(text)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("System")

            GroupBox("Startup") {
                Toggle("Launch Flowy at login", isOn: $draft.autostart)
            }

            GroupBox("Permissions") {
                VStack(alignment: .leading, spacing: 8) {
                    permissionRow("Speech Recognition", granted: model.permissions.speechAuthorized)
                    permissionRow("Microphone", granted: model.permissions.microphoneAuthorized)
                    permissionRow("Accessibility", granted: model.permissions.accessibilityTrusted)
                    Button {
                        TextOutput.requestAccessibilityAccess()
                        TextOutput.openAccessibilitySettings()
                    } label: {
                        Label("Open Accessibility Settings", systemImage: "gear")
                    }
                }
            }

            GroupBox("Config") {
                HStack {
                    Text(model.configPath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        NSWorkspace.shared.selectFile(AppConfig.configURL.path, inFileViewerRootedAtPath: "")
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                }
            }

            GroupBox("Build") {
                Text("Native Swift, macOS-only, arm64 release bundle.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var permissionBanners: some View {
        if !model.permissions.accessibilityTrusted {
            callout(
                title: "Accessibility permission required",
                message: "Required for pasting text. If Flowy is already listed in System Settings with the switch ON, remove it and re-add it — macOS invalidates accessibility trust each time the app is rebuilt.",
                actionTitle: "Request Access",
                action: {
                    TextOutput.requestAccessibilityAccess()
                    TextOutput.openAccessibilitySettings()
                }
            )
        }
        if !model.permissions.speechAuthorized {
            callout(
                title: "Speech Recognition not authorized",
                message: "Enable Flowy in System Settings > Privacy & Security > Speech Recognition.",
                actionTitle: "Request Permission",
                action: model.requestInitialPermissions
            )
        }
        if !model.permissions.microphoneAuthorized {
            callout(
                title: "Microphone not authorized",
                message: "Flowy needs microphone access before recording.",
                actionTitle: "Request Permission",
                action: model.requestInitialPermissions
            )
        }
    }

    private var inputDeviceBinding: Binding<String> {
        Binding(
            get: { draft.inputDevice ?? "" },
            set: { draft.inputDevice = $0.isEmpty ? nil : $0 }
        )
    }

    private var statusColor: Color {
        switch model.status {
        case .idle: return .secondary
        case .recording: return .red
        case .transcribing: return .accentColor
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 22, weight: .semibold))
    }

    private func callout(
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold)
                Text(message).foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionTitle, action: action)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func permissionRow(_ title: String, granted: Bool) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(title)
            Spacer()
            Text(granted ? "Granted" : "Missing")
                .foregroundStyle(.secondary)
        }
    }

    private func refreshDevices() {
        devices = AudioDeviceManager.inputDevices()
    }

    private func saveDraft() {
        var clean = draft
        clean.dictionary = collectedDictionary()
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
        runDictionaryTest()
    }

    private func collectedDictionary() -> [String: String] {
        var dictionary: [String: String] = [:]
        for row in dictRows {
            let key = row.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                dictionary[key] = value
            }
        }
        return dictionary
    }

    private func runDictionaryTest() {
        guard !dictionaryTestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            dictionaryTestOutput = "-"
            return
        }
        dictionaryTestOutput = DictionaryRewriter.apply(
            dictionaryTestInput,
            dictionary: collectedDictionary()
        )
    }

    private func checkOllama() async {
        ollamaMessage = "Checking..."
        let result = await OllamaClient.status(endpoint: draft.ollamaEndpoint)
        if result.reachable {
            ollamaModels = result.models
            if draft.ollamaModel.isEmpty, let first = result.models.first {
                draft.ollamaModel = first
            }
            ollamaMessage = "Connected. \(result.models.count) model\(result.models.count == 1 ? "" : "s") found."
        } else {
            ollamaModels = []
            ollamaMessage = result.error ?? "Could not reach Ollama."
        }
    }

    private static func rows(from dictionary: [String: String]) -> [DictionaryRow] {
        dictionary
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { DictionaryRow(key: $0.key, value: $0.value) }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case shortcut
    case audio
    case output
    case dictionary
    case ai
    case history
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortcut: return "Shortcut"
        case .audio: return "Audio"
        case .output: return "Output"
        case .dictionary: return "Dictionary"
        case .ai: return "AI"
        case .history: return "History"
        case .system: return "System"
        }
    }

    var symbol: String {
        switch self {
        case .shortcut: return "keyboard"
        case .audio: return "waveform"
        case .output: return "text.cursor"
        case .dictionary: return "book"
        case .ai: return "sparkles"
        case .history: return "clock.arrow.circlepath"
        case .system: return "gearshape"
        }
    }
}

private struct DictionaryRow: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
}
