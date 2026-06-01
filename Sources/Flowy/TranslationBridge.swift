import SwiftUI
import Translation   // macOS 14+; weak-linked so the binary runs on macOS 13

// MARK: – Language catalogue (always available)

struct TranslationLanguage: Identifiable {
    let id: String   // BCP-47
    let name: String

    static let supported: [TranslationLanguage] = [
        .init(id: "ar",      name: "Arabic"),
        .init(id: "zh-Hans", name: "Chinese (Simplified)"),
        .init(id: "zh-Hant", name: "Chinese (Traditional)"),
        .init(id: "nl",      name: "Dutch"),
        .init(id: "en",      name: "English"),
        .init(id: "fr",      name: "French"),
        .init(id: "de",      name: "German"),
        .init(id: "id",      name: "Indonesian"),
        .init(id: "it",      name: "Italian"),
        .init(id: "ja",      name: "Japanese"),
        .init(id: "ko",      name: "Korean"),
        .init(id: "pl",      name: "Polish"),
        .init(id: "pt",      name: "Portuguese"),
        .init(id: "ru",      name: "Russian"),
        .init(id: "es",      name: "Spanish"),
        .init(id: "th",      name: "Thai"),
        .init(id: "tr",      name: "Turkish"),
        .init(id: "uk",      name: "Ukrainian"),
        .init(id: "vi",      name: "Vietnamese"),
    ]
}

// MARK: – Translation bridge (macOS 14+)

@available(macOS 15, *)
@MainActor
final class TranslationBridge: ObservableObject {
    /// Setting this triggers `.translationTask` in TranslationBackgroundView.
    @Published private(set) var config: TranslationSession.Configuration?

    private var cachedSession: TranslationSession?
    private var cachedTargetBCP47: String?
    private var sessionWaiters: [CheckedContinuation<TranslationSession, Error>] = []

    func translate(_ text: String, targetLanguageBCP47: String) async throws -> String {
        let session = try await session(for: targetLanguageBCP47)
        let response = try await session.translate(text)
        return response.targetText
    }

    // Called by TranslationBackgroundView once a session is ready
    func sessionReady(_ session: TranslationSession) {
        cachedSession = session
        let waiters = sessionWaiters
        sessionWaiters.removeAll()
        waiters.forEach { $0.resume(returning: session) }
    }

    private func session(for bcp47: String) async throws -> TranslationSession {
        if let s = cachedSession, cachedTargetBCP47 == bcp47 { return s }

        cachedSession = nil
        cachedTargetBCP47 = bcp47
        config = TranslationSession.Configuration(
            source: nil,
            target: Locale.Language(identifier: bcp47)
        )

        return try await withCheckedThrowingContinuation { cont in
            sessionWaiters.append(cont)
        }
    }
}

// MARK: – Hidden host view (macOS 14+)

@available(macOS 15, *)
struct TranslationBackgroundView: View {
    @ObservedObject var bridge: TranslationBridge

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(bridge.config) { session in
                await MainActor.run { bridge.sessionReady(session) }
            }
    }
}
