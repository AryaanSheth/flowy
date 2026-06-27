import Foundation

struct AppConfig: Codable, Equatable {
    static let currentSchemaVersion = 7

    var schemaVersion: Int
    var hotkey: String
    var hotkeyMode: HotkeyMode
    var autostart: Bool
    var dictionary: [String: String]
    var inputDevice: String?
    var recognitionLocaleIdentifier: String?
    var recognitionBackend: RecognitionBackend
    var whisperModel: String
    var outputMode: OutputMode
    var liveStreamingEnabled: Bool
    var disabledAppBundleIDs: [String]
    var clipboardOnlyAppBundleIDs: [String]
    var avoidSecureTextFields: Bool
    var maxRecordingSecs: Int
    var historySize: Int
    var activeToneID: String?
    var customTones: [TonePreset]
    var experimentalFeaturesEnabled: Bool
    var translationEnabled: Bool
    var translationTargetLanguage: String
    var feedbackSoundsEnabled: Bool
    var activeMenuBarLabelEnabled: Bool
    var vadEnabled: Bool
    var vadSilenceSeconds: Double
    var vadSpeechThresholdDB: Double
    var ollamaEnabled: Bool
    var ollamaEndpoint: String
    var ollamaModel: String
    var ollamaPrompt: String

    init(
        schemaVersion: Int = AppConfig.currentSchemaVersion,
        hotkey: String = "Alt+Space",
        hotkeyMode: HotkeyMode = .hold,
        autostart: Bool = false,
        dictionary: [String: String] = [:],
        inputDevice: String? = nil,
        recognitionLocaleIdentifier: String? = nil,
        recognitionBackend: RecognitionBackend = .apple,
        whisperModel: String = "base",
        outputMode: OutputMode = .typeAndClipboard,
        liveStreamingEnabled: Bool = false,
        disabledAppBundleIDs: [String] = [],
        clipboardOnlyAppBundleIDs: [String] = [],
        avoidSecureTextFields: Bool = true,
        maxRecordingSecs: Int = 60,
        historySize: Int = 20,
        activeToneID: String? = nil,
        customTones: [TonePreset] = [],
        experimentalFeaturesEnabled: Bool = false,
        translationEnabled: Bool = false,
        translationTargetLanguage: String = "en",
        feedbackSoundsEnabled: Bool = true,
        activeMenuBarLabelEnabled: Bool = true,
        vadEnabled: Bool = true,
        vadSilenceSeconds: Double = 0.6,
        vadSpeechThresholdDB: Double = -25.0,
        ollamaEnabled: Bool = false,
        ollamaEndpoint: String = "http://localhost:11434",
        ollamaModel: String = "gemma3:1b",
        ollamaPrompt: String = AppConfig.defaultOllamaPrompt
    ) {
        self.schemaVersion = schemaVersion
        self.hotkey = hotkey
        self.hotkeyMode = hotkeyMode
        self.autostart = autostart
        self.dictionary = dictionary
        self.inputDevice = inputDevice
        self.recognitionLocaleIdentifier = recognitionLocaleIdentifier
        self.recognitionBackend = recognitionBackend
        self.whisperModel = whisperModel
        self.outputMode = outputMode
        self.liveStreamingEnabled = liveStreamingEnabled
        self.disabledAppBundleIDs = disabledAppBundleIDs
        self.clipboardOnlyAppBundleIDs = clipboardOnlyAppBundleIDs
        self.avoidSecureTextFields = avoidSecureTextFields
        self.maxRecordingSecs = maxRecordingSecs
        self.historySize = historySize
        self.activeToneID = activeToneID
        self.customTones = customTones
        self.experimentalFeaturesEnabled = experimentalFeaturesEnabled
        self.translationEnabled = translationEnabled
        self.translationTargetLanguage = translationTargetLanguage
        self.feedbackSoundsEnabled = feedbackSoundsEnabled
        self.activeMenuBarLabelEnabled = activeMenuBarLabelEnabled
        self.vadEnabled = vadEnabled
        self.vadSilenceSeconds = vadSilenceSeconds
        self.vadSpeechThresholdDB = vadSpeechThresholdDB
        self.ollamaEnabled = ollamaEnabled
        self.ollamaEndpoint = ollamaEndpoint
        self.ollamaModel = ollamaModel
        self.ollamaPrompt = ollamaPrompt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case hotkey
        case hotkeyMode
        case autostart
        case dictionary
        case inputDevice
        case recognitionLocaleIdentifier
        case recognitionBackend
        case whisperModel
        case outputMode
        case liveStreamingEnabled
        case disabledAppBundleIDs
        case clipboardOnlyAppBundleIDs
        case avoidSecureTextFields
        case maxRecordingSecs
        case historySize
        case activeToneID
        case customTones
        case experimentalFeaturesEnabled
        case translationEnabled
        case translationTargetLanguage
        case feedbackSoundsEnabled
        case activeMenuBarLabelEnabled
        case vadEnabled
        case vadSilenceSeconds
        case vadSpeechThresholdDB
        case ollamaEnabled
        case ollamaEndpoint
        case ollamaModel
        case ollamaPrompt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        let decodedSchemaVersion = schemaVersion
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? "Alt+Space"
        hotkeyMode = try c.decodeIfPresent(HotkeyMode.self, forKey: .hotkeyMode) ?? .hold
        autostart = try c.decodeIfPresent(Bool.self, forKey: .autostart) ?? false
        dictionary = try c.decodeIfPresent([String: String].self, forKey: .dictionary) ?? [:]
        inputDevice = try c.decodeIfPresent(String.self, forKey: .inputDevice)
        recognitionLocaleIdentifier = try c.decodeIfPresent(String.self, forKey: .recognitionLocaleIdentifier)
        recognitionBackend = try c.decodeIfPresent(RecognitionBackend.self, forKey: .recognitionBackend) ?? .apple
        whisperModel = try c.decodeIfPresent(String.self, forKey: .whisperModel) ?? "base"
        outputMode = try c.decodeIfPresent(OutputMode.self, forKey: .outputMode) ?? .typeAndClipboard
        liveStreamingEnabled = try c.decodeIfPresent(Bool.self, forKey: .liveStreamingEnabled) ?? false
        disabledAppBundleIDs = try c.decodeIfPresent([String].self, forKey: .disabledAppBundleIDs) ?? []
        clipboardOnlyAppBundleIDs = try c.decodeIfPresent([String].self, forKey: .clipboardOnlyAppBundleIDs) ?? []
        avoidSecureTextFields = try c.decodeIfPresent(Bool.self, forKey: .avoidSecureTextFields) ?? true
        maxRecordingSecs = try c.decodeIfPresent(Int.self, forKey: .maxRecordingSecs) ?? 60
        historySize = try c.decodeIfPresent(Int.self, forKey: .historySize) ?? 20
        activeToneID = try c.decodeIfPresent(String.self, forKey: .activeToneID)
        customTones = try c.decodeIfPresent([TonePreset].self, forKey: .customTones) ?? []
        experimentalFeaturesEnabled = try c.decodeIfPresent(Bool.self, forKey: .experimentalFeaturesEnabled) ?? false
        translationEnabled = try c.decodeIfPresent(Bool.self, forKey: .translationEnabled) ?? false
        translationTargetLanguage = try c.decodeIfPresent(String.self, forKey: .translationTargetLanguage) ?? "en"
        feedbackSoundsEnabled = try c.decodeIfPresent(Bool.self, forKey: .feedbackSoundsEnabled) ?? true
        activeMenuBarLabelEnabled = try c.decodeIfPresent(Bool.self, forKey: .activeMenuBarLabelEnabled) ?? true
        vadEnabled = try c.decodeIfPresent(Bool.self, forKey: .vadEnabled) ?? true
        vadSilenceSeconds = try c.decodeIfPresent(Double.self, forKey: .vadSilenceSeconds) ?? 0.6
        if decodedSchemaVersion < 4, abs(vadSilenceSeconds - 1.5) < 0.001 {
            vadSilenceSeconds = 0.6
        }
        let rawThreshold = try c.decodeIfPresent(Double.self, forKey: .vadSpeechThresholdDB) ?? -25.0
        vadSpeechThresholdDB = min(-10.0, max(-45.0, rawThreshold))
        ollamaEnabled = try c.decodeIfPresent(Bool.self, forKey: .ollamaEnabled) ?? false
        ollamaEndpoint = try c.decodeIfPresent(String.self, forKey: .ollamaEndpoint) ?? "http://localhost:11434"
        ollamaModel = try c.decodeIfPresent(String.self, forKey: .ollamaModel) ?? "gemma3:1b"
        if decodedSchemaVersion < 5, ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines) == "llama3.2:3b" {
            ollamaModel = "gemma3:1b"
        }
        ollamaPrompt = try c.decodeIfPresent(String.self, forKey: .ollamaPrompt) ?? AppConfig.defaultOllamaPrompt
        if decodedSchemaVersion < 6, Self.isLegacyDefaultOllamaPrompt(ollamaPrompt) {
            ollamaPrompt = AppConfig.defaultOllamaPrompt
        }
    }

    static let defaultOllamaPrompt = """
    Smart polish dictation. Infer intent; make unclear fragments coherent. Fix grammar, punctuation, capitalization, transcription errors, and self-corrections. Do not invent facts. Use bullets for lists, tasks, options, or pros/cons; numbered lists for ordered steps. Otherwise write a paragraph. Return only final text.
    """

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("flowy", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    static func load() -> AppConfig {
        let url = configURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AppConfig()
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AppConfig.self, from: data).sanitized()
        } catch {
            NSLog("Could not load config, using defaults: \(error.localizedDescription)")
            return AppConfig()
        }
    }

    func save() throws {
        let url = Self.configURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.flowy.encode(sanitized())
        try data.write(to: url, options: [.atomic])
    }

    func sanitized() -> AppConfig {
        var next = self
        let defaults = AppConfig()

        next.schemaVersion = Self.currentSchemaVersion

        next.hotkey = next.hotkey.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.hotkey.isEmpty {
            next.hotkey = defaults.hotkey
        }

        if let locale = next.recognitionLocaleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !locale.isEmpty,
           locale.lowercased() != "system" {
            next.recognitionLocaleIdentifier = locale
        } else {
            next.recognitionLocaleIdentifier = nil
        }

        if let device = next.inputDevice?.trimmingCharacters(in: .whitespacesAndNewlines), !device.isEmpty {
            next.inputDevice = device
        } else {
            next.inputDevice = nil
        }

        next.maxRecordingSecs = min(300, max(5, next.maxRecordingSecs))
        next.historySize = min(200, max(1, next.historySize))
        next.vadSilenceSeconds = min(5.0, max(0.5, next.vadSilenceSeconds))
        next.vadSpeechThresholdDB = min(-10.0, max(-45.0, next.vadSpeechThresholdDB))
        next.disabledAppBundleIDs = Self.cleanedBundleIDs(next.disabledAppBundleIDs)
        next.clipboardOnlyAppBundleIDs = Self.cleanedBundleIDs(next.clipboardOnlyAppBundleIDs)

        next.whisperModel = next.whisperModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.whisperModel.isEmpty {
            next.whisperModel = defaults.whisperModel
        }

        next.ollamaEndpoint = next.ollamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.ollamaEndpoint.isEmpty {
            next.ollamaEndpoint = defaults.ollamaEndpoint
        }

        next.ollamaModel = next.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.ollamaModel.isEmpty {
            next.ollamaModel = defaults.ollamaModel
        }

        next.ollamaPrompt = next.ollamaPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.ollamaPrompt.isEmpty {
            next.ollamaPrompt = defaults.ollamaPrompt
        }

        var cleanDictionary: [String: String] = [:]
        for (key, value) in next.dictionary {
            let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanKey.isEmpty {
                cleanDictionary[cleanKey] = cleanValue
            }
        }
        next.dictionary = cleanDictionary

        return next
    }

    private static func cleanedBundleIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var cleaned: [String] = []
        for id in ids {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            cleaned.append(trimmed)
        }
        return cleaned
    }

    private static func isLegacyDefaultOllamaPrompt(_ prompt: String) -> Bool {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "Clean dictation. Fix punctuation, capitalization, grammar, and spoken self-corrections. Preserve meaning. Return only the final text.",
            """
            You are a transcription cleaner. You receive raw speech-to-text output labeled "Input:" and must return only the cleaned version after "Output:". Fix punctuation, capitalization, and grammar. If the speaker self-corrects using phrases like "actually", "I mean", "I meant", "scratch that", or "no wait", apply the correction and output only the final intended text with the amendment resolved. Otherwise, preserve the speaker's exact words and meaning. Never ask questions, never add explanations or commentary. Return only the cleaned text.
            """.trimmingCharacters(in: .whitespacesAndNewlines),
        ].contains(normalized)
    }
}

extension JSONEncoder {
    static var flowy: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
