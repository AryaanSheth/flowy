import AudioToolbox
import AVFoundation
import Speech

final class SpeechRecorder {
    // VAD uses adaptive thresholds relative to peak speaking volume so it works
    // in both quiet rooms and noisy offices without manual tuning.
    // speechStartDB is configurable per-recording via start(); default shown here.
    private static let defaultSpeechStartDB: Float = -25.0
    // After speech detected, silence = drop this many dB below peak speaking volume.
    private static let silenceDropDB: Float  = 22.0   // e.g. peak -12 → silence threshold -34
    private static let deepSilenceDropDB: Float = 35.0 // e.g. peak -12 → deep silence threshold -47
    private static let silenceDBFloor: Float  = -52.0  // absolute floor for silence threshold
    private static let deepSilenceDBFloor: Float = -65.0 // absolute floor for deep silence threshold
    private static let deepSilenceFactor: Double = 0.18  // fire at 18% of timeout in deep silence

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
    private var vadSilenceTimeout: TimeInterval = 1.0
    private var vadSpeechStartDB: Float = -25.0
    private var vadLastSpeechNs: UInt64 = 0
    private var vadSpeakerDetected = false
    private var vadFired = false
    private var vadPeakDB: Float = -160.0  // max dBFS observed during speech phase

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
        vadSpeechStartDB = vadSpeechThresholdDB
        vadLastSpeechNs = DispatchTime.now().uptimeNanoseconds
        vadSpeakerDetected = false
        vadFired = false
        vadPeakDB = -160.0

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

        if db >= vadSpeechStartDB {
            vadSpeakerDetected = true
            vadLastSpeechNs = DispatchTime.now().uptimeNanoseconds
            if db > vadPeakDB { vadPeakDB = db }
            return
        }

        guard vadSpeakerDetected else { return }

        // Adaptive thresholds: derived from peak speaking volume so they work in
        // both quiet rooms and noisy offices. A speaker at -12 dBFS gets:
        //   silenceThreshold ≈ -34  (was hardcoded -40, too low for typical rooms)
        //   deepThreshold    ≈ -47  (was hardcoded -55, almost never triggered)
        let silenceThreshold = max(Self.silenceDBFloor, vadPeakDB - Self.silenceDropDB)
        let deepThreshold    = max(Self.deepSilenceDBFloor, vadPeakDB - Self.deepSilenceDropDB)

        if db > silenceThreshold {
            // Still within ambient noise band of the speaking level — reset clock
            vadLastSpeechNs = DispatchTime.now().uptimeNanoseconds
            return
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - vadLastSpeechNs) / 1e9
        let timeout = db < deepThreshold
            ? vadSilenceTimeout * Self.deepSilenceFactor
            : vadSilenceTimeout
        if elapsed >= timeout {
            vadFired = true
            DispatchQueue.main.async { vadCallback() }
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
