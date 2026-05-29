import Foundation

enum FloweyError: Error, LocalizedError {
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
        case .type: return "Paste into the focused window"
        case .clipboard: return "Copy text without pasting"
        case .typeAndClipboard: return "Paste and leave text on the clipboard"
        }
    }
}

struct PermissionState: Equatable {
    var speechAuthorized: Bool = false
    var microphoneAuthorized: Bool = false
    var accessibilityTrusted: Bool = false
}
