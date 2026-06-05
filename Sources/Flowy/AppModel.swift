import AppKit
import AVFoundation
import ServiceManagement
import Speech

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var status: AppStatus = .idle
    @Published private(set) var config: AppConfig
    @Published private(set) var history: [String] = []
    @Published private(set) var permissions = PermissionState()
    @Published var lastError: String?

    var onStatusChanged: ((AppStatus) -> Void)?
    var onHotkeyChanged: ((String) -> Void)?
    /// Set by AppDelegate on macOS 14+ to provide Apple Translation support.
    var translateText: ((String, String) async throws -> String)?

    private let speechRecorder = SpeechRecorder()
    private let streamingInjector = StreamingInjector()
    private var capturedApp: NSRunningApplication?
    private var recordingTimeout: DispatchWorkItem?
    private var streamingEnabledForRecording = false

    init(config: AppConfig = .load()) {
        self.config = config
        refreshPermissions()
    }

    var configPath: String {
        AppConfig.configURL.path
    }

    func requestInitialPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.refreshPermissions()
                if status == .authorized {
                    self?.speechRecorder.warmUpRecognizer()
                }
            }
        }

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.refreshPermissions()
                if granted {
                    FlowyLog.info("Microphone access authorized")
                }
            }
        }
    }

    func refreshPermissions() {
        permissions = PermissionState(
            speechAuthorized: SFSpeechRecognizer.authorizationStatus() == .authorized,
            microphoneAuthorized: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibilityTrusted: AXIsProcessTrusted()
        )
    }

    func saveConfig(_ nextConfig: AppConfig) throws {
        let oldConfig = config
        let clean = nextConfig.sanitized()
        try clean.save()
        config = clean

        if oldConfig.hotkey != clean.hotkey {
            onHotkeyChanged?(clean.hotkey)
        }

        if oldConfig.autostart != clean.autostart {
            applyAutostart(enabled: clean.autostart)
        }
    }

    func startRecording() {
        guard status == .idle else { return }

        lastError = nil
        FlowyLog.info("Recording start requested")
        refreshPermissions()
        guard permissions.microphoneAuthorized else {
            lastError = "Microphone access is not authorized."
            FlowyLog.warn("Recording blocked: microphone is not authorized")
            requestInitialPermissions()
            return
        }
        guard permissions.speechAuthorized else {
            lastError = "Speech Recognition is not authorized."
            FlowyLog.warn("Recording blocked: speech recognition is not authorized")
            requestInitialPermissions()
            return
        }

        capturedApp = NSWorkspace.shared.frontmostApplication
        streamingInjector.reset()
        streamingEnabledForRecording = config.outputMode != .clipboard && AXIsProcessTrusted()

        do {
            setStatus(.recording)
            FlowyLog.info("Recording started inputDevice=\(config.inputDevice ?? "default")")
            let vadStop: (() -> Void)? = config.vadEnabled ? { [weak self] in
                Task { @MainActor in
                    FlowyLog.info("VAD silence detected — stopping recording")
                    self?.stopRecording()
                }
            } : nil
            try speechRecorder.start(
                deviceUID: config.inputDevice,
                maxSeconds: config.maxRecordingSecs,
                onPartial: { [weak self] text in
                    Task { @MainActor in self?.handlePartialRecognition(text) }
                },
                onVADStop: vadStop,
                vadSilenceSeconds: config.vadSilenceSeconds,
                vadSpeechThresholdDB: Float(config.vadSpeechThresholdDB)
            ) { [weak self] result in
                Task { @MainActor in self?.handleRecognition(result) }
            }
            scheduleRecordingTimeout()
        } catch {
            capturedApp = nil
            recordingTimeout?.cancel()
            setStatus(.idle)
            lastError = error.localizedDescription
            FlowyLog.error("Recording start failed: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard status == .recording else { return }
        FlowyLog.info("Recording stop requested")
        // Pre-activate the target app now so the focus switch happens
        // concurrently with transcription rather than after it.
        capturedApp?.activate(options: [.activateIgnoringOtherApps])
        recordingTimeout?.cancel()
        recordingTimeout = nil
        setStatus(.transcribing)
        speechRecorder.stop()
    }

    func clearHistory() {
        history.removeAll()
    }

    private func scheduleRecordingTimeout() {
        recordingTimeout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.stopRecording() }
        }
        recordingTimeout = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .seconds(config.maxRecordingSecs),
            execute: item
        )
    }

    private func handleRecognition(_ result: Result<String, Error>) {
        recordingTimeout?.cancel()
        recordingTimeout = nil

        Task { @MainActor in
            await processRecognition(result)
        }
    }

    private func handlePartialRecognition(_ rawText: String) {
        guard streamingEnabledForRecording, status == .recording else { return }

        let text = prepareRecognizedText(
            rawText,
            config: config
        )
        guard !text.isEmpty else { return }

        streamingInjector.update(to: text)
    }

    private func processRecognition(_ result: Result<String, Error>) async {
        defer {
            capturedApp = nil
            streamingEnabledForRecording = false
            streamingInjector.reset()
            setStatus(.idle)
        }

        let rawText: String
        switch result {
        case .success(let text):
            rawText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            FlowyLog.info("Speech result chars=\(rawText.count)")
        case .failure(let error):
            lastError = normalizedSpeechError(error)
            FlowyLog.error("Speech failed: \(lastError ?? error.localizedDescription)")
            return
        }

        guard !rawText.isEmpty else {
            lastError = "No speech was recognized. Check that Dictation is enabled and the selected microphone is receiving audio."
            FlowyLog.warn("Speech returned empty text")
            return
        }

        let snapshot = config
        var text = prepareRecognizedText(
            rawText,
            config: snapshot
        )

        // Resolve the effective Ollama prompt: active tone overrides ollamaPrompt.
        // An empty prompt (Raw tone) means skip Ollama entirely.
        let allTones = TonePreset.builtIns + snapshot.customTones
        let activeTone = snapshot.activeToneID.flatMap { id in allTones.first { $0.id == id } }
        let effectivePrompt: String?
        if let tone = activeTone {
            effectivePrompt = tone.prompt.isEmpty ? nil : tone.prompt
        } else if snapshot.ollamaEnabled {
            effectivePrompt = snapshot.ollamaPrompt
        } else {
            effectivePrompt = nil
        }

        if effectivePrompt == nil {
            text = AmendmentRewriter.apply(text)
        }

        if let prompt = effectivePrompt {
            let started = Date()
            let toneLabel = activeTone?.name ?? "ollama"
            FlowyLog.info("Ollama enhancement started tone=\(toneLabel) model=\(snapshot.ollamaModel)")
            do {
                let enhanced = try await OllamaClient.enhance(
                    endpoint: snapshot.ollamaEndpoint,
                    model: snapshot.ollamaModel,
                    system: prompt,
                    text: text
                )
                if !enhanced.isEmpty { text = enhanced }
            } catch {
                FlowyLog.warn("Ollama enhancement failed: \(error.localizedDescription)")
            }
            let latency = Date().timeIntervalSince(started)
            FlowyLog.info(String(format: "Ollama enhancement latency %.2fs", latency))
        }

        if snapshot.translationEnabled, let translate = translateText {
            let started = Date()
            FlowyLog.info("Translation started target=\(snapshot.translationTargetLanguage)")
            do {
                let translated = try await translate(text, snapshot.translationTargetLanguage)
                if !translated.isEmpty { text = translated }
            } catch {
                FlowyLog.warn("Translation failed: \(error.localizedDescription)")
            }
            FlowyLog.info(String(format: "Translation latency %.2fs", Date().timeIntervalSince(started)))
        }

        history.insert(text, at: 0)
        if history.count > snapshot.historySize {
            history.removeLast(history.count - snapshot.historySize)
        }

        let delivered: Bool
        if streamingInjector.isActive {
            if snapshot.outputMode == .typeAndClipboard {
                TextOutput.copyToClipboard(text)
            }
            delivered = streamingInjector.update(to: text)
            if !delivered {
                TextOutput.copyToClipboard(text)
            }
        } else {
            delivered = await TextOutput.deliver(text, mode: snapshot.outputMode, capturedApp: capturedApp)
        }
        FlowyLog.info("Delivery finished ok=\(delivered) mode=\(snapshot.outputMode.rawValue)")
        if !delivered, snapshot.outputMode != .clipboard {
            lastError = "Auto-paste failed — text is in your clipboard. Open Settings › System › Permissions and re-grant Accessibility access. If Flowy is already listed, remove it and re-add it (each rebuild resets the trust)."
            FlowyLog.error(lastError ?? "Delivery failed")
        }
    }

    private func prepareRecognizedText(
        _ rawText: String,
        config: AppConfig
    ) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        text = DictionaryRewriter.apply(text, dictionary: config.dictionary)
        text = PunctuationRewriter.apply(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func setStatus(_ nextStatus: AppStatus) {
        guard status != nextStatus else { return }
        status = nextStatus
        onStatusChanged?(nextStatus)
    }

    private func applyAutostart(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Autostart update failed: \(error.localizedDescription)")
        }
    }

    private func normalizedSpeechError(_ error: Error) -> String {
        let message = error.localizedDescription
        let lower = message.lowercased()
        if lower.contains("siri") || lower.contains("dictation") {
            return "macOS says Siri and Dictation are disabled. Enable Dictation in System Settings > Keyboard > Dictation, then try again."
        }
        return message
    }
}
