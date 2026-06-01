import Foundation

struct AppConfig: Codable, Equatable {
    var hotkey: String
    var autostart: Bool
    var dictionary: [String: String]
    var inputDevice: String?
    var outputMode: OutputMode
    var maxRecordingSecs: Int
    var historySize: Int
    var activeToneID: String?
    var customTones: [TonePreset]
    var translationEnabled: Bool
    var translationTargetLanguage: String
    var vadEnabled: Bool
    var vadSilenceSeconds: Double
    var vadSpeechThresholdDB: Double
    var ollamaEnabled: Bool
    var ollamaEndpoint: String
    var ollamaModel: String
    var ollamaPrompt: String

    init(
        hotkey: String = "CmdOrCtrl+Shift+Space",
        autostart: Bool = false,
        dictionary: [String: String] = [:],
        inputDevice: String? = nil,
        outputMode: OutputMode = .type,
        maxRecordingSecs: Int = 60,
        historySize: Int = 20,
        activeToneID: String? = nil,
        customTones: [TonePreset] = [],
        translationEnabled: Bool = false,
        translationTargetLanguage: String = "en",
        vadEnabled: Bool = true,
        vadSilenceSeconds: Double = 0.6,
        vadSpeechThresholdDB: Double = -25.0,
        ollamaEnabled: Bool = false,
        ollamaEndpoint: String = "http://localhost:11434",
        ollamaModel: String = "llama3.2:3b",
        ollamaPrompt: String = AppConfig.defaultOllamaPrompt
    ) {
        self.hotkey = hotkey
        self.autostart = autostart
        self.dictionary = dictionary
        self.inputDevice = inputDevice
        self.outputMode = outputMode
        self.maxRecordingSecs = maxRecordingSecs
        self.historySize = historySize
        self.activeToneID = activeToneID
        self.customTones = customTones
        self.translationEnabled = translationEnabled
        self.translationTargetLanguage = translationTargetLanguage
        self.vadEnabled = vadEnabled
        self.vadSilenceSeconds = vadSilenceSeconds
        self.vadSpeechThresholdDB = vadSpeechThresholdDB
        self.ollamaEnabled = ollamaEnabled
        self.ollamaEndpoint = ollamaEndpoint
        self.ollamaModel = ollamaModel
        self.ollamaPrompt = ollamaPrompt
    }

    enum CodingKeys: String, CodingKey {
        case hotkey
        case autostart
        case dictionary
        case inputDevice
        case outputMode
        case maxRecordingSecs
        case historySize
        case activeToneID
        case customTones
        case translationEnabled
        case translationTargetLanguage
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
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? "CmdOrCtrl+Shift+Space"
        autostart = try c.decodeIfPresent(Bool.self, forKey: .autostart) ?? false
        dictionary = try c.decodeIfPresent([String: String].self, forKey: .dictionary) ?? [:]
        inputDevice = try c.decodeIfPresent(String.self, forKey: .inputDevice)
        outputMode = try c.decodeIfPresent(OutputMode.self, forKey: .outputMode) ?? .type
        maxRecordingSecs = try c.decodeIfPresent(Int.self, forKey: .maxRecordingSecs) ?? 60
        historySize = try c.decodeIfPresent(Int.self, forKey: .historySize) ?? 20
        activeToneID = try c.decodeIfPresent(String.self, forKey: .activeToneID)
        customTones = try c.decodeIfPresent([TonePreset].self, forKey: .customTones) ?? []
        translationEnabled = try c.decodeIfPresent(Bool.self, forKey: .translationEnabled) ?? false
        translationTargetLanguage = try c.decodeIfPresent(String.self, forKey: .translationTargetLanguage) ?? "en"
        vadEnabled = try c.decodeIfPresent(Bool.self, forKey: .vadEnabled) ?? true
        vadSilenceSeconds = try c.decodeIfPresent(Double.self, forKey: .vadSilenceSeconds) ?? 0.6
        vadSpeechThresholdDB = try c.decodeIfPresent(Double.self, forKey: .vadSpeechThresholdDB) ?? -25.0
        ollamaEnabled = try c.decodeIfPresent(Bool.self, forKey: .ollamaEnabled) ?? false
        ollamaEndpoint = try c.decodeIfPresent(String.self, forKey: .ollamaEndpoint) ?? "http://localhost:11434"
        ollamaModel = try c.decodeIfPresent(String.self, forKey: .ollamaModel) ?? "llama3.2:3b"
        ollamaPrompt = try c.decodeIfPresent(String.self, forKey: .ollamaPrompt) ?? AppConfig.defaultOllamaPrompt
    }

    static let defaultOllamaPrompt = """
    You are a transcription cleaner. You receive raw speech-to-text output labeled "Input:" and must return only the cleaned version after "Output:". Fix punctuation, capitalization, and grammar. If the speaker self-corrects using phrases like "actually", "I mean", "I meant", "scratch that", or "no wait", apply the correction and output only the final intended text with the amendment resolved. Otherwise, preserve the speaker's exact words and meaning. Never ask questions, never add explanations or commentary. Return only the cleaned text.
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

        next.hotkey = next.hotkey.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.hotkey.isEmpty {
            next.hotkey = defaults.hotkey
        }

        if let device = next.inputDevice?.trimmingCharacters(in: .whitespacesAndNewlines), !device.isEmpty {
            next.inputDevice = device
        } else {
            next.inputDevice = nil
        }

        next.maxRecordingSecs = min(300, max(5, next.maxRecordingSecs))
        next.historySize = min(200, max(1, next.historySize))
        next.vadSilenceSeconds = min(3.0, max(0.3, next.vadSilenceSeconds))
        next.vadSpeechThresholdDB = min(-5.0, max(-50.0, next.vadSpeechThresholdDB))

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
}

extension JSONEncoder {
    static var flowy: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
