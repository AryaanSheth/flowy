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

    private var recorder: SpeechRecorder?
    private var capturedApp: NSRunningApplication?
    private var recordingTimeout: DispatchWorkItem?

    init(config: AppConfig = .load()) {
        self.config = config
        refreshPermissions()
    }

    var configPath: String {
        AppConfig.configURL.path
    }

    func requestInitialPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
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
        refreshPermissions()
        guard permissions.speechAuthorized else {
            lastError = "Speech Recognition is not authorized."
            requestInitialPermissions()
            return
        }

        capturedApp = NSWorkspace.shared.frontmostApplication
        let recorder = SpeechRecorder()
        self.recorder = recorder

        do {
            setStatus(.recording)
            try recorder.start(
                deviceUID: config.inputDevice,
                maxSeconds: config.maxRecordingSecs
            ) { [weak self] result in
                Task { @MainActor in self?.handleRecognition(result) }
            }
            scheduleRecordingTimeout()
        } catch {
            self.recorder = nil
            capturedApp = nil
            recordingTimeout?.cancel()
            setStatus(.idle)
            lastError = error.localizedDescription
        }
    }

    func stopRecording() {
        guard status == .recording else { return }
        recordingTimeout?.cancel()
        recordingTimeout = nil
        setStatus(.transcribing)
        recorder?.stop()
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
        recorder = nil

        Task { @MainActor in
            await processRecognition(result)
        }
    }

    private func processRecognition(_ result: Result<String, Error>) async {
        defer {
            capturedApp = nil
            setStatus(.idle)
        }

        let rawText: String
        switch result {
        case .success(let text):
            rawText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .failure(let error):
            lastError = normalizedSpeechError(error)
            return
        }

        guard !rawText.isEmpty else {
            lastError = "No speech was recognized. Check that Dictation is enabled and the selected microphone is receiving audio."
            return
        }

        let snapshot = config
        var text = DictionaryRewriter.apply(rawText, dictionary: snapshot.dictionary)

        if snapshot.ollamaEnabled {
            let started = Date()
            do {
                let enhanced = try await OllamaClient.enhance(
                    endpoint: snapshot.ollamaEndpoint,
                    model: snapshot.ollamaModel,
                    system: snapshot.ollamaPrompt,
                    text: text
                )
                if !enhanced.isEmpty {
                    text = enhanced
                }
            } catch {
                NSLog("Ollama enhancement failed: \(error.localizedDescription)")
            }
            NSLog("Ollama enhancement latency: %.2fs", Date().timeIntervalSince(started))
        }

        history.insert(text, at: 0)
        if history.count > snapshot.historySize {
            history.removeLast(history.count - snapshot.historySize)
        }

        let delivered = await TextOutput.deliver(text, mode: snapshot.outputMode, capturedApp: capturedApp)
        if !delivered, snapshot.outputMode != .clipboard {
            lastError = "Copied to clipboard, but automatic paste failed. Check Flowey in System Settings > Privacy & Security > Accessibility."
        }
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
