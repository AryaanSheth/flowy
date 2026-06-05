import AudioToolbox
import AVFoundation
import Speech

final class SpeechRecorder {
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)

    // Incremented on every start() — stale callbacks bail out on mismatch.
    private var generation = 0

    // Per-recording state
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var completion: ((Result<String, Error>) -> Void)?
    private var bestText = ""
    private var finished = false
    private var stopping = false
    private var tapInstalled = false
    private var finalTimeout: DispatchWorkItem?

    // VAD: fires when the recognizer produces no new text for vadSilenceTimeout seconds.
    // This is transcription-stability based — the speech engine already knows when
    // speech has stopped, so no microphone level calibration is needed.
    private var vadCallback: (() -> Void)?
    private var vadSilenceTimeout: TimeInterval = 0.6
    private var vadWorkItem: DispatchWorkItem?
    private var vadFired = false

    // MARK: – Warm-up

    func warmUpRecognizer() {
        guard recognizer?.isAvailable == true,
              SFSpeechRecognizer.authorizationStatus() == .authorized else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = false
        req.taskHint = .dictation
        if recognizer?.supportsOnDeviceRecognition == true {
            req.requiresOnDeviceRecognition = true
        }
        let task = recognizer?.recognitionTask(with: req) { _, _ in }
        req.endAudio()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { task?.cancel() }
        FlowyLog.info("SpeechRecorder recognizer warm-up started")
    }

    // MARK: – Recording

    func start(
        deviceUID: String?,
        maxSeconds: Int,
        onPartial: ((String) -> Void)? = nil,
        onVADStop: (() -> Void)? = nil,
        vadSilenceSeconds: TimeInterval = 0.6,
        vadSpeechThresholdDB: Float = -25.0,
        completion: @escaping (Result<String, Error>) -> Void
    ) throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw FlowyError.message("Speech Recognition is not authorized")
        }
        guard recognizer != nil else {
            throw FlowyError.message("Speech Recognition is unavailable for the current locale")
        }
        guard recognizer?.isAvailable == true else {
            throw FlowyError.message("macOS Speech Recognition is unavailable. Enable Siri and Dictation in System Settings, then try again.")
        }

        generation &+= 1
        let myGeneration = generation

        self.completion = completion
        bestText = ""
        finished = false
        stopping = false
        finalTimeout = nil
        vadCallback = onVADStop
        vadSilenceTimeout = vadSilenceSeconds
        vadWorkItem?.cancel()
        vadWorkItem = nil
        vadFired = false

        try configureInputDevice(uid: deviceUID)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self, self.generation == myGeneration else { return }

            if let text = result?.bestTranscription.formattedString, !text.isEmpty {
                let changed = text != self.bestText
                self.bestText = text

                if changed {
                    onPartial?(text)
                }

                // Reschedule VAD timer every time new text arrives.
                // When text stops changing (user stopped talking), the timer fires.
                if changed, let cb = self.vadCallback, !self.stopping, !self.vadFired {
                    self.scheduleVAD(cb: cb, generation: myGeneration)
                }
            }

            if result?.isFinal == true {
                self.finish(.success(self.bestText))
                return
            }

            if self.stopping, !self.bestText.isEmpty {
                self.finish(.success(self.bestText))
                return
            }

            if let error {
                if self.stopping, !self.bestText.isEmpty {
                    self.finish(.success(self.bestText))
                } else {
                    self.finish(.failure(Self.normalizedSpeechError(error)))
                }
            }
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw FlowyError.message("No microphone input format is available")
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        tapInstalled = true

        try engine.start()
    }

    func stop() {
        guard !stopping else { return }
        stopping = true
        vadWorkItem?.cancel()
        vadWorkItem = nil

        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()

        if !bestText.isEmpty {
            recognitionRequest?.endAudio()
            finish(.success(bestText))
            return
        }

        recognitionRequest?.endAudio()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finish(.success(self.bestText))
        }
        finalTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150), execute: timeout)
    }

    // MARK: – Transcription-stability VAD

    private func scheduleVAD(cb: @escaping () -> Void, generation: Int) {
        vadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.generation == generation,
                  !self.stopping, !self.vadFired else { return }
            self.vadFired = true
            FlowyLog.info("VAD: silence detected after transcription stabilised")
            cb()
        }
        vadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + vadSilenceTimeout, execute: item)
    }

    // MARK: – Finish

    private func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true

        vadWorkItem?.cancel()
        vadWorkItem = nil
        finalTimeout?.cancel()
        finalTimeout = nil

        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        completion?(result)
        completion = nil
    }

    // MARK: – Device configuration

    private func configureInputDevice(uid: String?) throws {
        guard let uid, !uid.isEmpty else { return }
        guard var deviceID = AudioDeviceManager.audioDeviceID(forUID: uid) else {
            throw FlowyError.message("Selected input device was not found")
        }
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw FlowyError.message("No microphone audio unit is available")
        }

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw FlowyError.message("Could not switch to the selected microphone")
        }
    }

    private static func normalizedSpeechError(_ error: Error) -> Error {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("siri") || msg.contains("dictation") {
            return FlowyError.message("macOS says Siri and Dictation are disabled. Enable Dictation in System Settings > Keyboard > Dictation, then try again.")
        }
        return error
    }
}
