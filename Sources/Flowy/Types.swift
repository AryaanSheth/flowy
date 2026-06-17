import Foundation

enum FlowyError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

enum AppStatus: String {
    case idle = "Idle"
    case recording = "Recording"
    case transcribing = "Transcribing"

    var label: String {
        switch self {
        case .idle: return "idle"
        case .recording: return "recording"
        case .transcribing: return "transcribing"
        }
    }

    var systemImageName: String {
        switch self {
        case .idle: return "mic"
        case .recording: return "record.circle.fill"
        case .transcribing: return "waveform"
        }
    }
}

enum OutputMode: String, Codable, CaseIterable, Identifiable {
    case type
    case clipboard
    case typeAndClipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .type: return "Inject"
        case .clipboard: return "Clipboard only"
        case .typeAndClipboard: return "Both"
        }
    }

    var subtitle: String {
        switch self {
        case .type: return "Paste into the focused window and restore clipboard"
        case .clipboard: return "Copy text without pasting"
        case .typeAndClipboard: return "Paste and leave text on the clipboard"
        }
    }
}

enum OutputModeResolver {
    static func effectiveMode(
        configuredMode: OutputMode,
        capturedBundleID: String?,
        clipboardOnlyBundleIDs: [String],
        accessibilityTrusted: Bool
    ) -> OutputMode {
        if let capturedBundleID, clipboardOnlyBundleIDs.contains(capturedBundleID) {
            return .clipboard
        }

        if configuredMode != .clipboard && !accessibilityTrusted {
            return .clipboard
        }

        return configuredMode
    }

    static func shouldStreamPartials(
        configuredMode: OutputMode,
        capturedBundleID: String?,
        clipboardOnlyBundleIDs: [String],
        accessibilityTrusted: Bool
    ) -> Bool {
        effectiveMode(
            configuredMode: configuredMode,
            capturedBundleID: capturedBundleID,
            clipboardOnlyBundleIDs: clipboardOnlyBundleIDs,
            accessibilityTrusted: accessibilityTrusted
        ) != .clipboard
    }
}

enum HotkeyMode: String, Codable, CaseIterable, Identifiable {
    case hold
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hold: return "Hold"
        case .toggle: return "Toggle"
        }
    }

    var subtitle: String {
        switch self {
        case .hold: return "Hold the hotkey to record, release to stop"
        case .toggle: return "Tap once to start, tap again to stop"
        }
    }
}

struct PermissionState: Equatable {
    var speechAuthorized: Bool = false
    var microphoneAuthorized: Bool = false
    var accessibilityTrusted: Bool = false
}

struct DictationStats: Equatable {
    var totalWords: Int = 0
    var totalDurationSeconds: Double = 0
    var lastWordCount: Int = 0
    var lastWPM: Int = 0
    var lastDurationSeconds: Double = 0

    private static let totalWordsKey = "stats.totalWords"
    private static let totalDurationSecondsKey = "stats.totalDurationSeconds"
    private static let lastWordCountKey = "stats.lastWordCount"
    private static let lastWPMKey = "stats.lastWPM"
    private static let lastDurationSecondsKey = "stats.lastDurationSeconds"

    var overallWPM: Int {
        guard totalWords > 0, totalDurationSeconds > 0 else { return 0 }
        return max(1, Int((Double(totalWords) / (totalDurationSeconds / 60)).rounded()))
    }

    static func load(defaults: UserDefaults = .standard) -> DictationStats {
        DictationStats(
            totalWords: defaults.integer(forKey: totalWordsKey),
            totalDurationSeconds: defaults.double(forKey: totalDurationSecondsKey),
            lastWordCount: defaults.integer(forKey: lastWordCountKey),
            lastWPM: defaults.integer(forKey: lastWPMKey),
            lastDurationSeconds: defaults.double(forKey: lastDurationSecondsKey)
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(totalWords, forKey: Self.totalWordsKey)
        defaults.set(totalDurationSeconds, forKey: Self.totalDurationSecondsKey)
        defaults.set(lastWordCount, forKey: Self.lastWordCountKey)
        defaults.set(lastWPM, forKey: Self.lastWPMKey)
        defaults.set(lastDurationSeconds, forKey: Self.lastDurationSecondsKey)
    }

    func addingRecording(words: Int, durationSeconds: Double) -> DictationStats {
        let safeDuration = max(1, durationSeconds)
        let wpm = max(1, Int((Double(words) / (safeDuration / 60)).rounded()))
        return DictationStats(
            totalWords: totalWords + words,
            totalDurationSeconds: totalDurationSeconds + safeDuration,
            lastWordCount: words,
            lastWPM: wpm,
            lastDurationSeconds: safeDuration
        )
    }
}
