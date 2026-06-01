import AudioToolbox
import AVFoundation
import Speech

final class SpeechRecorder {
    // dBFS thresholds for VAD
    private static let speechStartDB: Float  = -25.0  // must reach this to arm silence tracking
    private static let silenceDB: Float      = -40.0  // below this = silence; resets timer if above
    private static let deepSilenceDB: Float  = -55.0  // near-zero signal: fire at 35% of timeout
    private static let deepSilenceFactor: Double = 0.35

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)

    // Incremented on every start() — stale callbacks from the previous
    // recording check their captured generation and early-return.
    private var generation = 0

    // Tracks whether engine.prepare() has been called since last stop().
    private var isPrepared = false

    // Per-recording state — reset at the top of start()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var completion: ((Result<String, Error>) -> Void)?
    private var bestText = ""
    private var finished = false
    private var stopping = false
    private var tapInstalled = false
    private var finalTimeout: DispatchWorkItem?

    // VAD state — written only from the audio tap thread after initialisation
    private var vadCallback: (() -> Void)?
    private var vadSilenceTimeout: TimeInterval = 1.5
    private var vadLastSpeechNs: UInt64 = 0
    private var vadSpeakerDetected = false
    private var vadFired = false

    // MARK: – Warm-up

    /// Pre-prepare the audio engine so the next start() skips engine.prepare().
    /// Call at launch and immediately after each recording finishes.
    func warmUp(deviceUID: String?) {
        guard !engine.isRunning else { return }
        try? configureInputDevice(uid: deviceUID)
        engine.prepare()
        isPrepared = true
        FlowyLog.info("SpeechRecorder engine warmed up")
    }

    /// Load the on-device speech model by running a brief dummy recognition task.
    /// Call once after speech authorisation is granted.
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

        // Increment generation — any callbacks still in flight from the
        // previous recording will see a generation mismatch and bail out.
        generation &+= 1
        let myGeneration = generation

        // Reset per-recording state
        self.completion = completion
        bestText = ""
        finished = false
        stopping = false
        finalTimeout = nil
        vadCallback = onVADStop
        vadSilenceTimeout = vadSilenceSeconds
        vadLastSpeechNs = DispatchTime.now().uptimeNanoseconds
        vadSpeakerDetected = false
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

        // 512 frames ≈ 11 ms at 48 kHz — checks silence ~4× more often than 2048
        input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self, weak request] buffer, _ in
            request?.append(buffer)
            self?.checkVAD(buffer)
        }
        tapInstalled = true

        // Only prepare if warmUp() hasn't already done so.
        if !isPrepared { engine.prepare() }
        try engine.start()
        isPrepared = false  // engine.stop() will de-prepare; track that we're now running
    }

    func stop() {
        guard !stopping else { return }
        stopping = true

        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()

        // Deliver bestText immediately — no need to wait for isFinal.
        if !bestText.isEmpty {
            recognitionRequest?.endAudio()
            finish(.success(bestText))
            return
        }

        // Very short recording with no partial result yet — wait briefly.
        recognitionRequest?.endAudio()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finish(.success(self.bestText))
        }
        finalTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150), execute: timeout)
    }

    // MARK: – VAD (audio tap thread)

    private func checkVAD(_ buffer: AVAudioPCMBuffer) {
        guard let vadCallback, !stopping, !vadFired else { return }
        let db = Self.rmsDB(buffer)
        if db >= Self.speechStartDB {
            vadSpeakerDetected = true
            vadLastSpeechNs = DispatchTime.now().uptimeNanoseconds
        } else if vadSpeakerDetected {
            if db > Self.silenceDB {
                // Ambient noise — not yet silent, reset the clock
                vadLastSpeechNs = DispatchTime.now().uptimeNanoseconds
            } else {
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - vadLastSpeechNs) / 1e9
                // Deep silence (near-zero signal): use a fraction of the normal timeout
                // so the recording stops almost immediately after the user finishes speaking.
                let threshold = db < Self.deepSilenceDB
                    ? vadSilenceTimeout * Self.deepSilenceFactor
                    : vadSilenceTimeout
                if elapsed >= threshold {
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

    // MARK: – Finish

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
        isPrepared = false
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
