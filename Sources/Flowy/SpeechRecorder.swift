import AudioToolbox
import AVFoundation
import Speech

final class SpeechRecorder {
    private let finalGraceNanoseconds: UInt64 = 450_000_000

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var completion: ((Result<String, Error>) -> Void)?
    private var bestText = ""
    private var finished = false
    private var stopping = false
    private var tapInstalled = false
    private var finalTimeout: DispatchWorkItem?

    func start(
        deviceUID: String?,
        maxSeconds: Int,
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

        self.completion = completion

        try configureInputDevice(uid: deviceUID)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let text = result?.bestTranscription.formattedString, !text.isEmpty {
                self.bestText = text
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

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        tapInstalled = true

        engine.prepare()
        try engine.start()
    }

    func stop() {
        guard !stopping else { return }
        stopping = true

        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        recognitionRequest?.endAudio()

        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finish(.success(self.bestText))
        }
        finalTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(finalGraceNanoseconds)), execute: timeout)
    }

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

    private func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true

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

    private static func normalizedSpeechError(_ error: Error) -> Error {
        let message = error.localizedDescription
        let lower = message.lowercased()
        if lower.contains("siri") || lower.contains("dictation") {
            return FlowyError.message("macOS says Siri and Dictation are disabled. Enable Dictation in System Settings > Keyboard > Dictation, then try again.")
        }
        return error
    }
}
