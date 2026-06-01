import AudioToolbox
import AVFoundation
import Speech

final class SpeechRecorder {
    private let finalGraceNanoseconds: UInt64 = 450_000_000

    // dBFS: must reach this level at least once before silence tracking begins
    private static let speechStartDB: Float = -25.0
    // dBFS: below this is treated as silence
    private static let silenceDB: Float = -40.0

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

    // VAD state — written only from the audio tap thread after initialization
    private var vadCallback: (() -> Void)?
    private var vadSilenceTimeout: TimeInterval = 1.5
    private var vadLastSpeechNs: UInt64 = 0
    private var vadSpeakerDetected = false
    private var vadFired = false

    func start(
        deviceUID: String?,
        maxSeconds: Int,
        onVADStop: (() -> Void)? = nil,
        vadSilenceSeconds: TimeInterval = 1.5,
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
        self.vadCallback = onVADStop
        self.vadSilenceTimeout = vadSilenceSeconds
        self.vadLastSpeechNs = DispatchTime.now().uptimeNanoseconds

        try configureInputDevice(uid: deviceUID)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
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

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self, weak request] buffer, _ in
            request?.append(buffer)
            self?.checkVAD(buffer)
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

        // If we already have a partial result, deliver it immediately.
        // Waiting for isFinal adds 500 ms–3 s with no meaningful accuracy gain —
        // partial results are accurate by the time the user stops recording.
        if !bestText.isEmpty {
            recognitionRequest?.endAudio()
            finish(.success(bestText))
            return
        }

        // No partial result yet (very short recording) — signal end and wait
        // briefly for the first recognition callback to arrive.
        recognitionRequest?.endAudio()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finish(.success(self.bestText))
        }
        finalTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150), execute: timeout)
    }

    // Called from the audio tap thread — intentionally avoids locks for performance.
    // Worst-case races (e.g. reading `stopping` a buffer late) resolve safely because
    // stopRecording() is idempotent and vadFired prevents double-dispatch.
    private func checkVAD(_ buffer: AVAudioPCMBuffer) {
        guard let vadCallback, !stopping, !vadFired else { return }
        let db = Self.rmsDB(buffer)
        if db >= Self.speechStartDB {
            vadSpeakerDetected = true
            vadLastSpeechNs = DispatchTime.now().uptimeNanoseconds
        } else if vadSpeakerDetected {
            if db > Self.silenceDB {
                // Soft sound resets the silence clock
                vadLastSpeechNs = DispatchTime.now().uptimeNanoseconds
            } else {
                let elapsedSecs = Double(DispatchTime.now().uptimeNanoseconds - vadLastSpeechNs) / 1e9
                if elapsedSecs >= vadSilenceTimeout {
                    vadFired = true
                    DispatchQueue.main.async { vadCallback() }
                }
            }
        }
    }

    private static func rmsDB(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return -160 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(n))
        return rms > 0 ? 20 * log10(rms) : -160
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
