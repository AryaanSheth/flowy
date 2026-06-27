import AudioToolbox
import AVFoundation
import WhisperKit

/// Local Whisper recognition backend (WhisperKit / CoreML).
///
/// ponytail: v1 does not stream partials or run VAD — Whisper transcribes the
/// whole utterance on stop. Live streaming injection, live WPM, and silence
/// auto-stop only work on the Apple backend. Add chunked streaming
/// (WhisperKit AudioStreamTranscriber) if/when the on-stop latency matters.
final class WhisperRecorder {
    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!

    // A single in-flight model load, reused across recordings until the model changes.
    private var loadTask: Task<WhisperKit, Error>?
    private var loadedModelName = ""

    // Per-recording state. `samples` is written on the audio thread and read on
    // stop() after the tap is removed and the engine flushed, so no lock needed.
    // ponytail: relies on removeTap()/engine.stop() draining in-flight callbacks.
    private var generation = 0
    private var stopping = false
    private var tapInstalled = false
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private var currentModel = "base"
    private var completion: ((Result<String, Error>) -> Void)?
    private var onLevel: ((Double) -> Void)?
    private var lastLevelSentAt: TimeInterval = 0

    // MARK: – Warm-up

    /// Kick off model load (and first-run download) ahead of recording.
    func warmUp(model: String) {
        _ = modelTask(for: model)
    }

    private func modelTask(for model: String) -> Task<WhisperKit, Error> {
        if let loadTask, loadedModelName == model { return loadTask }
        loadedModelName = model
        let task = Task { () -> WhisperKit in
            try await WhisperKit(WhisperKitConfig(model: model))
        }
        loadTask = task
        return task
    }

    // MARK: – Recording

    func start(
        deviceUID: String?,
        model: String,
        onLevel: ((Double) -> Void)? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) throws {
        generation &+= 1
        stopping = false
        samples.removeAll(keepingCapacity: true)
        currentModel = model
        self.completion = completion
        self.onLevel = onLevel
        lastLevelSentAt = 0

        warmUp(model: model)
        try configureInputDevice(uid: deviceUID)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw FlowyError.message("No microphone input format is available")
        }
        converter = AVAudioConverter(from: format, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.appendBuffer(buffer)
        }
        tapInstalled = true

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
        onLevel?(0)

        let audio = samples
        let model = currentModel
        let gen = generation
        Task { [weak self] in
            guard let self else { return }
            do {
                guard !audio.isEmpty else {
                    self.deliver(.success(""), gen: gen)
                    return
                }
                let whisper = try await self.modelTask(for: model).value
                let results = try await whisper.transcribe(audioArray: audio)
                let text = results.map(\.text).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self.deliver(.success(text), gen: gen)
            } catch {
                self.deliver(.failure(error), gen: gen)
            }
        }
    }

    // MARK: – Audio capture

    private func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        if let onLevel,
           SpeechRecorder.shouldEmitLevel(
               now: ProcessInfo.processInfo.systemUptime,
               lastSentAt: &lastLevelSentAt
           ) {
            onLevel(SpeechRecorder.normalizedLevel(from: buffer))
        }

        guard let converter, buffer.frameLength > 0 else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if let error {
            FlowyLog.warn("Whisper resample failed: \(error.localizedDescription)")
            return
        }
        if let channel = out.floatChannelData, out.frameLength > 0 {
            samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
        }
    }

    private func deliver(_ result: Result<String, Error>, gen: Int) {
        Task { @MainActor in
            guard gen == self.generation else { return }
            let callback = self.completion
            self.completion = nil
            callback?(result)
        }
    }

    // MARK: – Device configuration

    // ponytail: duplicated from SpeechRecorder rather than extracted — two call
    // sites, ~15 lines. Extract to a shared helper if a third backend appears.
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
}
