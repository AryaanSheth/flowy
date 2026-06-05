import AppKit
import AVFoundation
import SwiftUI

// MARK: – Glass blur background
private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// MARK: – Design tokens (glass palette)
private enum G {
    static let text    = Color.white
    static let dim     = Color.white.opacity(0.48)
    static let faint   = Color.white.opacity(0.22)
    static let border  = Color.white.opacity(0.09)
    static let fill    = Color.white.opacity(0.055)
    static let teal    = Color(red: 0.10, green: 0.80, blue: 0.72)
    static let danger  = Color(red: 1.00, green: 0.38, blue: 0.35)
    static let warn    = Color(red: 0.96, green: 0.77, blue: 0.28)
}

// MARK: – Button styles
private struct PrimaryBtn: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(G.teal.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct NudgeBtn: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(configuration.isPressed ? G.teal.opacity(0.6) : G.faint)
    }
}

private struct GlassField: TextFieldStyle {
    // swiftlint:disable:next identifier_name
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 12))
            .foregroundStyle(G.text)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(G.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(G.border, lineWidth: 1))
    }
}

private struct Divider: View {
    var body: some View { G.border.frame(height: 1) }
}

// MARK: – Main view
struct SettingsView: View {
    @ObservedObject var model: AppModel

    @State private var draft: AppConfig
    @State private var tab: Tab = .record
    @State private var devices: [AudioInputDevice] = []
    @State private var dictRows: [DictRow]
    @State private var testInput  = ""
    @State private var testOutput = "—"
    @State private var saveMsg    = ""
    @State private var hoveredTab: Tab?   = nil
    @State private var hoveredHistory: Int? = nil
    @State private var autosaveTask: Task<Void, Never>? = nil

    private let permissionTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(model: AppModel) {
        self.model = model
        _draft    = State(initialValue: model.config)
        _dictRows = State(initialValue: Self.dictRows(from: model.config.dictionary))
    }

    var body: some View {
        ZStack {
            VisualEffect(material: .hudWindow, blending: .behindWindow)
                .ignoresSafeArea()
            Color(red: 0.08, green: 0.09, blue: 0.10).opacity(0.82)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                HStack(spacing: 0) {
                    sidebar
                    content
                }
                footer
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { refreshDevices(); model.refreshPermissions() }
        .onReceive(permissionTimer) { _ in model.refreshPermissions() }
        .onChange(of: draft)    { _ in scheduleAutosave() }
        .onChange(of: dictRows) { _ in scheduleAutosave() }
    }

    // MARK: – Header
    private var header: some View {
        HStack(spacing: 10) {
            // Wave logo
            Canvas { ctx, size in
                var p = Path()
                let h = size.height, w = size.width
                p.move(to: .init(x: 0, y: h * 0.5))
                p.addCurve(to: .init(x: w * 0.5, y: h * 0.5),
                           control1: .init(x: w * 0.15, y: h * 0.1),
                           control2: .init(x: w * 0.35, y: h * 0.9))
                p.addCurve(to: .init(x: w, y: h * 0.5),
                           control1: .init(x: w * 0.65, y: h * 0.1),
                           control2: .init(x: w * 0.85, y: h * 0.9))
                ctx.stroke(p, with: .color(.white),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .frame(width: 20, height: 11)

            Text("flowy")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(G.text)
                .tracking(-0.3)

            Spacer()

            HStack(spacing: 5) {
                Circle().fill(statusDot).frame(width: 5, height: 5)
                Text(model.status.label)
                    .font(.system(size: 11))
                    .foregroundStyle(G.dim)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(G.fill)
        .overlay(alignment: .bottom) { G.border.frame(height: 1) }
    }

    // MARK: – Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Tab.allCases) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { tab = t }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: t.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(tab == t ? G.teal : (hoveredTab == t ? G.dim : G.faint))
                            .frame(width: 14)
                        Text(t.label)
                            .font(.system(size: 12, weight: tab == t ? .medium : .regular))
                            .foregroundStyle(tab == t ? G.text : G.dim)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(
                        tab == t ? G.fill : (hoveredTab == t ? G.fill.opacity(0.6) : .clear),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .overlay(alignment: .leading) {
                        if tab == t {
                            G.teal.frame(width: 2)
                                .clipShape(RoundedRectangle(cornerRadius: 1))
                                .padding(.vertical, 6)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .onHover { isHovered in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        hoveredTab = isHovered ? t : nil
                    }
                }
            }
            Spacer()
        }
        .padding(.top, 10)
        .frame(width: 158)
        .overlay(alignment: .trailing) { G.border.frame(width: 1) }
    }

    // MARK: – Content
    private var content: some View {
        ScrollView {
            Group {
                switch tab {
                case .record:     recordTab
                case .dictionary: dictionaryTab
                case .history:    historyTab
                case .system:     systemTab
                }
            }
            .id(tab)
            .transition(.opacity)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: – Footer
    private var footer: some View {
        HStack(spacing: 6) {
            if let error = model.lastError ?? (saveMsg.isEmpty ? nil : saveMsg) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(G.danger)
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(G.danger)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(G.fill)
        .overlay(alignment: .top) { G.border.frame(height: 1) }
    }

    // MARK: – Tabs

    private var recordTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabTitle("Record")
            permBanners

            // Hold-to-record button
            VStack(alignment: .leading, spacing: 6) {
                HoldRecordButton(
                    isRecording: model.status == .recording,
                    onPress: model.startRecording,
                    onRelease: model.stopRecording
                )
                .frame(maxWidth: .infinity, minHeight: 34)
                Text("Hold to record · text appears live")
                    .font(.system(size: 11))
                    .foregroundStyle(G.faint)
            }
            .padding(.bottom, 20)

            glassCard {
                // Hotkey
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hotkey").font(.system(size: 13)).foregroundStyle(G.text)
                        Text("Click, then press your keys")
                            .font(.system(size: 10)).foregroundStyle(G.faint)
                        Button("reset to ⌥Space") { draft.hotkey = "Alt+Space" }
                            .font(.system(size: 10)).foregroundStyle(G.faint).buttonStyle(.plain)
                    }
                    Spacer()
                    HotkeyRecorderView(hotkey: $draft.hotkey).frame(width: 180, height: 28)
                }
                .padding(.vertical, 10).padding(.horizontal, 14)

                Divider().padding(.horizontal, 14)

                // Input device
                row("Microphone") {
                    HStack(spacing: 8) {
                        Picker("", selection: inputDeviceBinding) {
                            Text("System default").tag("")
                            ForEach(devices) { d in Text(d.name).tag(d.uid) }
                        }
                        .labelsHidden().frame(width: 180)
                        Button { refreshDevices() } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10))
                        }.buttonStyle(NudgeBtn())
                    }
                }

                Divider().padding(.horizontal, 14)

                // Recording limit
                row("Max duration") {
                    HStack(spacing: 6) {
                        Text("\(draft.maxRecordingSecs) s")
                            .font(.system(size: 12)).foregroundStyle(G.text)
                            .frame(width: 36, alignment: .trailing)
                        Stepper("", value: $draft.maxRecordingSecs, in: 5...300, step: 5)
                            .labelsHidden()
                    }
                }

                Divider().padding(.horizontal, 14)

                // Auto-stop
                row("Auto-stop on silence") {
                    Toggle("", isOn: $draft.vadEnabled).labelsHidden().tint(G.teal)
                }

                if draft.vadEnabled {
                    Divider().padding(.horizontal, 14)
                    row("Silence delay") {
                        HStack(spacing: 6) {
                            Text(String(format: "%.1f s", draft.vadSilenceSeconds))
                                .font(.system(size: 12)).foregroundStyle(G.text)
                                .frame(width: 36, alignment: .trailing)
                            Stepper("", value: $draft.vadSilenceSeconds, in: 0.5...5.0, step: 0.5)
                                .labelsHidden()
                        }
                    }
                }
            }
        }
    }

    private var dictionaryTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            tabTitle("Dictionary")
            glassCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(dictRows.indices, id: \.self) { i in
                        HStack(spacing: 6) {
                            TextField("word", text: $dictRows[i].key)
                                .textFieldStyle(GlassField())
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10)).foregroundStyle(G.faint)
                            TextField("replacement", text: $dictRows[i].value)
                                .textFieldStyle(GlassField())
                            Button { dictRows.remove(at: i); runTest() } label: {
                                Image(systemName: "xmark").font(.system(size: 10))
                            }.buttonStyle(NudgeBtn())
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        if i < dictRows.count - 1 { Divider().padding(.horizontal, 14) }
                    }
                    if dictRows.isEmpty {
                        Text("No substitutions yet")
                            .font(.system(size: 12)).foregroundStyle(G.faint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    Divider().padding(.horizontal, 14)
                    Button { dictRows.append(DictRow(key: "", value: "")) } label: {
                        Label("Add word", systemImage: "plus").font(.system(size: 11))
                    }
                    .buttonStyle(NudgeBtn())
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Preview").font(.system(size: 11)).foregroundStyle(G.faint)
                TextField("Type to test…", text: $testInput)
                    .textFieldStyle(GlassField())
                    .onChange(of: testInput) { _ in runTest() }
                Text(testOutput)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(G.dim)
            }
        }
    }

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                tabTitle("History")
                Spacer()
                Button { model.clearHistory() } label: {
                    Text("Clear").font(.system(size: 11))
                }
                .buttonStyle(NudgeBtn())
                .disabled(model.history.isEmpty)
            }
            if model.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 24)).foregroundStyle(G.border)
                    Text("No transcriptions yet")
                        .font(.system(size: 13)).foregroundStyle(G.faint)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.history.enumerated()), id: \.offset) { idx, text in
                        HStack(alignment: .top, spacing: 10) {
                            Text(text)
                                .font(.system(size: 12)).foregroundStyle(G.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button { TextOutput.copyToClipboard(text) } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundStyle(hoveredHistory == idx ? G.dim : G.faint)
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(
                            hoveredHistory == idx
                                ? Color.white.opacity(0.07)
                                : G.fill,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                hoveredHistory == idx ? G.border.opacity(2) : G.border,
                                lineWidth: 1
                            ))
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onHover { isHovered in
                            withAnimation(.easeInOut(duration: 0.12)) {
                                hoveredHistory = isHovered ? idx : nil
                            }
                        }
                    }
                }
            }
        }
    }

    private var systemTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabTitle("System")
            glassCard {
                row("Launch at login") {
                    Toggle("", isOn: $draft.autostart).labelsHidden().tint(G.teal)
                }

                Divider().padding(.horizontal, 14)
                permRow("Speech Recognition", ok: model.permissions.speechAuthorized)
                Divider().padding(.horizontal, 14)
                permRow("Microphone",         ok: model.permissions.microphoneAuthorized)
                Divider().padding(.horizontal, 14)
                permRow("Accessibility",       ok: model.permissions.accessibilityTrusted)
                Divider().padding(.horizontal, 14)

                Button {
                    TextOutput.requestAccessibilityAccess()
                    TextOutput.openAccessibilitySettings()
                } label: {
                    Label("Open Accessibility Settings", systemImage: "lock.open")
                        .font(.system(size: 12))
                }
                .buttonStyle(NudgeBtn())
                .padding(.horizontal, 14).padding(.vertical, 10)

                Divider().padding(.horizontal, 14)

                HStack(spacing: 8) {
                    Text(model.configPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(G.faint)
                        .textSelection(.enabled)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        NSWorkspace.shared.selectFile(AppConfig.configURL.path, inFileViewerRootedAtPath: "")
                    } label: {
                        Image(systemName: "folder").font(.system(size: 11))
                    }.buttonStyle(NudgeBtn())
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
    }

    // MARK: – Shared components

    @ViewBuilder
    private var permBanners: some View {
        if !model.permissions.accessibilityTrusted {
            banner("Accessibility required — remove and re-add Flowy if already listed.",
                   action: { TextOutput.requestAccessibilityAccess(); TextOutput.openAccessibilitySettings() },
                   label: "Fix")
        }
        if !model.permissions.speechAuthorized {
            banner("Speech Recognition not authorized.",
                   action: model.requestInitialPermissions, label: "Request")
        }
        if !model.permissions.microphoneAuthorized {
            banner("Microphone access required.",
                   action: model.requestInitialPermissions, label: "Request")
        }
    }

    private func tabTitle(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(G.text)
            .padding(.bottom, 14)
    }

    @ViewBuilder
    private func glassCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(G.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(G.border, lineWidth: 1))
    }

    private func row<C: View>(_ label: String, @ViewBuilder control: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 13)).foregroundStyle(G.text)
            Spacer()
            control()
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
    }

    private func permRow(_ title: String, ok: Bool) -> some View {
        HStack {
            Circle().fill(ok ? G.teal : G.danger.opacity(0.8)).frame(width: 5, height: 5)
            Text(title).font(.system(size: 13)).foregroundStyle(G.text)
            Spacer()
            Text(ok ? "granted" : "missing")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ok ? G.teal.opacity(0.8) : G.danger.opacity(0.8))
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
    }

    private func banner(_ msg: String, action: @escaping () -> Void, label: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(G.warn).frame(width: 5, height: 5)
            Text(msg).font(.system(size: 11)).foregroundStyle(G.dim)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(label, action: action)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(G.warn).buttonStyle(.plain)
        }
        .padding(.vertical, 7).padding(.bottom, 4)
    }

    // MARK: – Logic

    private var inputDeviceBinding: Binding<String> {
        Binding(get: { draft.inputDevice ?? "" },
                set: { draft.inputDevice = $0.isEmpty ? nil : $0 })
    }

    private var statusDot: Color {
        switch model.status {
        case .idle:         return G.faint
        case .recording:    return G.danger
        case .transcribing: return G.text
        }
    }

    private func refreshDevices() { devices = AudioDeviceManager.inputDevices() }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            // Skip if nothing actually changed (e.g. post-save sync triggered this)
            guard draft != model.config || collectedDict() != model.config.dictionary else { return }
            saveDraft()
        }
    }

    private func saveDraft() {
        var c = draft
        c.dictionary = collectedDict()
        c.outputMode = .typeAndClipboard
        do {
            try model.saveConfig(c)
            saveMsg = ""
            // Sync draft to the sanitized saved config. This triggers onChange again,
            // but scheduleAutosave's guard (draft == model.config) will no-op it.
            draft    = model.config
            dictRows = Self.dictRows(from: model.config.dictionary)
            runTest()
        } catch {
            saveMsg = error.localizedDescription
        }
    }

    private func collectedDict() -> [String: String] {
        var r: [String: String] = [:]
        for row in dictRows {
            let k = row.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let v = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !k.isEmpty { r[k] = v }
        }
        return r
    }

    private func runTest() {
        guard !testInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            testOutput = "—"; return
        }
        testOutput = DictionaryRewriter.apply(testInput, dictionary: collectedDict())
    }

    private static func dictRows(from d: [String: String]) -> [DictRow] {
        d.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
         .map { DictRow(key: $0.key, value: $0.value) }
    }
}

// MARK: – Tab enum
private enum Tab: String, CaseIterable, Identifiable {
    case record, dictionary, history, system
    var id: String { rawValue }

    var label: String {
        switch self {
        case .record:     "Record"
        case .dictionary: "Dictionary"
        case .history:    "History"
        case .system:     "System"
        }
    }

    var icon: String {
        switch self {
        case .record:     "waveform"
        case .dictionary: "book"
        case .history:    "clock.arrow.circlepath"
        case .system:     "gearshape"
        }
    }
}

// MARK: – DictRow
private struct DictRow: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
}
