import Foundation
import XCTest
@testable import Flowy

final class FlowyLogicTests: XCTestCase {
    func testDictionaryRewriterUsesPhraseBoundariesAndLongestMatchFirst() {
        let dictionary = [
            "flowy": "Flowy",
            "new york": "New York",
            "api": "API",
        ]

        let text = "flowy sent the api result to new york, not chloe"
        XCTAssertEqual(
            DictionaryRewriter.apply(text, dictionary: dictionary),
            "Flowy sent the API result to New York, not chloe"
        )
    }

    func testPunctuationRewriterHandlesCommandsAndSpacing() {
        XCTAssertEqual(
            PunctuationRewriter.apply("hello comma new line world exclamation mark"),
            "hello,\nworld! "
        )
    }

    func testAmendmentRewriterKeepsFinalIntent() {
        XCTAssertEqual(
            AmendmentRewriter.apply("Send it to Sam, no wait, send it to Priya"),
            "Send it to Priya"
        )
    }

    func testLegacyConfigDecodesAndMigratesToCurrentSchema() throws {
        let json = """
        {
          "hotkey": "Alt+Space",
          "dictionary": { "flowy": "Flowy" },
          "maxRecordingSecs": 999,
          "vadSpeechThresholdDB": -99
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.hotkeyMode, .hold)
        XCTAssertNil(decoded.recognitionLocaleIdentifier)
        XCTAssertFalse(decoded.experimentalFeaturesEnabled)
        XCTAssertFalse(decoded.liveStreamingEnabled)

        let migrated = decoded.sanitized()
        XCTAssertEqual(migrated.schemaVersion, AppConfig.currentSchemaVersion)
        XCTAssertEqual(migrated.maxRecordingSecs, 300)
        XCTAssertEqual(migrated.vadSpeechThresholdDB, -45)
        XCTAssertEqual(migrated.dictionary, ["flowy": "Flowy"])
    }

    func testV3DefaultVADSilenceMigratesToFasterStop() throws {
        let json = """
        {
          "schemaVersion": 3,
          "vadSilenceSeconds": 1.5
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)

        XCTAssertEqual(decoded.vadSilenceSeconds, 0.6)
        XCTAssertEqual(decoded.sanitized().schemaVersion, AppConfig.currentSchemaVersion)
    }

    func testLegacyDefaultOllamaModelMigratesToFastModel() throws {
        let json = """
        {
          "schemaVersion": 4,
          "ollamaModel": "llama3.2:3b"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)

        XCTAssertEqual(decoded.ollamaModel, "gemma3:1b")
        XCTAssertEqual(decoded.sanitized().schemaVersion, AppConfig.currentSchemaVersion)
    }

    func testLegacyDefaultOllamaPromptMigratesToSmartPolish() throws {
        let json = """
        {
          "schemaVersion": 5,
          "ollamaPrompt": "Clean dictation. Fix punctuation, capitalization, grammar, and spoken self-corrections. Preserve meaning. Return only the final text."
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)

        XCTAssertEqual(decoded.ollamaPrompt, AppConfig.defaultOllamaPrompt)
        XCTAssertTrue(decoded.ollamaPrompt.localizedCaseInsensitiveContains("coherent"))
        XCTAssertTrue(decoded.ollamaPrompt.localizedCaseInsensitiveContains("bullets"))
    }

    func testConfigSanitizesSystemLocaleToNil() {
        let config = AppConfig(
            schemaVersion: 0,
            hotkey: " ",
            recognitionLocaleIdentifier: " system ",
            disabledAppBundleIDs: [" com.apple.Terminal ", "com.apple.Terminal", ""],
            clipboardOnlyAppBundleIDs: [" com.example.App "],
            ollamaEndpoint: " ",
            ollamaModel: " "
        ).sanitized()

        XCTAssertEqual(config.schemaVersion, AppConfig.currentSchemaVersion)
        XCTAssertEqual(config.hotkey, "Alt+Space")
        XCTAssertNil(config.recognitionLocaleIdentifier)
        XCTAssertEqual(config.disabledAppBundleIDs, ["com.apple.Terminal"])
        XCTAssertEqual(config.clipboardOnlyAppBundleIDs, ["com.example.App"])
        XCTAssertEqual(config.ollamaEndpoint, "http://localhost:11434")
        XCTAssertEqual(config.ollamaModel, "gemma3:1b")
    }

    func testEffectiveOutputModeHonorsClipboardOnlyAppRule() {
        let config = AppConfig(
            outputMode: .typeAndClipboard,
            clipboardOnlyAppBundleIDs: ["com.example.Notes"]
        )

        XCTAssertEqual(
            OutputModeResolver.effectiveMode(
                configuredMode: config.outputMode,
                capturedBundleID: "com.example.Notes",
                clipboardOnlyBundleIDs: config.clipboardOnlyAppBundleIDs,
                accessibilityTrusted: true
            ),
            .clipboard
        )
    }

    func testEffectiveOutputModeFallsBackToClipboardWithoutAccessibility() {
        XCTAssertEqual(
            OutputModeResolver.effectiveMode(
                configuredMode: .type,
                capturedBundleID: "com.example.Editor",
                clipboardOnlyBundleIDs: [],
                accessibilityTrusted: false
            ),
            .clipboard
        )

        XCTAssertEqual(
            OutputModeResolver.effectiveMode(
                configuredMode: .clipboard,
                capturedBundleID: nil,
                clipboardOnlyBundleIDs: [],
                accessibilityTrusted: false
            ),
            .clipboard
        )
    }

    func testStreamingPartialsFollowEffectiveOutputMode() {
        XCTAssertTrue(
            OutputModeResolver.shouldStreamPartials(
                liveStreamingEnabled: true,
                configuredMode: .typeAndClipboard,
                capturedBundleID: "com.example.Editor",
                clipboardOnlyBundleIDs: [],
                accessibilityTrusted: true
            )
        )

        XCTAssertFalse(
            OutputModeResolver.shouldStreamPartials(
                liveStreamingEnabled: false,
                configuredMode: .typeAndClipboard,
                capturedBundleID: "com.example.Editor",
                clipboardOnlyBundleIDs: [],
                accessibilityTrusted: true
            )
        )

        XCTAssertFalse(
            OutputModeResolver.shouldStreamPartials(
                liveStreamingEnabled: true,
                configuredMode: .typeAndClipboard,
                capturedBundleID: "com.example.Notes",
                clipboardOnlyBundleIDs: ["com.example.Notes"],
                accessibilityTrusted: true
            )
        )

        XCTAssertFalse(
            OutputModeResolver.shouldStreamPartials(
                liveStreamingEnabled: true,
                configuredMode: .type,
                capturedBundleID: "com.example.Editor",
                clipboardOnlyBundleIDs: [],
                accessibilityTrusted: false
            )
        )
    }

    func testLocalPolishPromptResolutionUsesOllamaWithoutExperimentalGate() {
        XCTAssertEqual(
            LocalPolishResolver.prompt(
                ollamaEnabled: true,
                activeToneID: "clean",
                customTones: [],
                fallbackPrompt: "fallback"
            ),
            TonePreset.builtIns.first { $0.id == "clean" }?.prompt
        )

        XCTAssertNil(
            LocalPolishResolver.prompt(
                ollamaEnabled: true,
                activeToneID: "raw",
                customTones: [],
                fallbackPrompt: "fallback"
            )
        )

        XCTAssertEqual(
            LocalPolishResolver.prompt(
                ollamaEnabled: true,
                activeToneID: nil,
                customTones: [],
                fallbackPrompt: "fallback"
            ),
            "fallback"
        )

        XCTAssertNil(
            LocalPolishResolver.prompt(
                ollamaEnabled: false,
                activeToneID: "clean",
                customTones: [],
                fallbackPrompt: "fallback"
            )
        )
    }

    func testLocalPolishPolicyUsesShortBlockingBudget() {
        XCTAssertLessThanOrEqual(LocalPolishResolver.maxBlockingSeconds, 1.5)
        XCTAssertLessThanOrEqual(LocalPolishResolver.requestTimeoutSeconds, 2.0)
        XCTAssertGreaterThanOrEqual(LocalPolishResolver.requestTimeoutSeconds, LocalPolishResolver.maxBlockingSeconds)
    }

    func testOllamaGenerationPolicyCapsResponseTokens() {
        XCTAssertEqual(
            OllamaGenerationPolicy.maxResponseTokens(for: "short note"),
            48
        )

        let longText = Array(repeating: "word", count: 500).joined(separator: " ")
        XCTAssertEqual(
            OllamaGenerationPolicy.maxResponseTokens(for: longText),
            256
        )
    }

    func testOllamaWarmUpPolicyIsTinyAndShortLived() {
        XCTAssertLessThanOrEqual(LocalPolishResolver.warmUpTimeoutSeconds, 1.0)
        XCTAssertEqual(OllamaGenerationPolicy.warmUpMaxResponseTokens, 1)
    }

    func testRecommendedOllamaModelDefaultsToFastOneBModel() {
        XCTAssertEqual(OllamaManager.recommendedModels.first?.name, "gemma3:1b")
        XCTAssertEqual(OllamaManager.recommendedModels.first?.tagline, "Recommended")
    }

    func testBuiltInPolishPromptsStayCompactForLatency() {
        XCTAssertLessThanOrEqual(AppConfig.defaultOllamaPrompt.count, 520)

        for tone in TonePreset.builtIns where !tone.prompt.isEmpty {
            XCTAssertLessThanOrEqual(tone.prompt.count, 520, tone.name)
        }
    }

    func testDefaultAndCleanPromptsUseSmartPolishBehavior() {
        let cleanPrompt = TonePreset.builtIns.first { $0.id == "clean" }?.prompt ?? ""

        XCTAssertEqual(cleanPrompt, AppConfig.defaultOllamaPrompt)
        XCTAssertTrue(cleanPrompt.localizedCaseInsensitiveContains("coherent"))
        XCTAssertTrue(cleanPrompt.localizedCaseInsensitiveContains("do not invent"))
        XCTAssertTrue(cleanPrompt.localizedCaseInsensitiveContains("bullets"))
        XCTAssertTrue(cleanPrompt.localizedCaseInsensitiveContains("numbered"))
        XCTAssertTrue(cleanPrompt.localizedCaseInsensitiveContains("return only"))
    }

    func testSpeechRecorderThrottlesLevelUpdates() {
        var lastSentAt: TimeInterval = 0

        XCTAssertTrue(SpeechRecorder.shouldEmitLevel(now: 10.0, lastSentAt: &lastSentAt, minInterval: 0.1))
        XCTAssertEqual(lastSentAt, 10.0)
        XCTAssertFalse(SpeechRecorder.shouldEmitLevel(now: 10.05, lastSentAt: &lastSentAt, minInterval: 0.1))
        XCTAssertEqual(lastSentAt, 10.0)
        XCTAssertTrue(SpeechRecorder.shouldEmitLevel(now: 10.11, lastSentAt: &lastSentAt, minInterval: 0.1))
        XCTAssertEqual(lastSentAt, 10.11)
    }

    func testStreamingPlannerTreatsLargeRecognizerResetAsAppendOnlyContinuation() {
        let committed = "This is a long dictated paragraph with enough words to be well past the rollback threshold. It should never be deleted just because recognition restarts."
        let resetPartial = "recognition restarts and then continues with the next sentence"

        let continuation = StreamingContinuationPlanner.continuationText(
            committed: committed,
            resetTarget: resetPartial,
            maxLiveRollbackCharacters: 48
        )

        XCTAssertEqual(continuation, " and then continues with the next sentence")
    }

    func testStreamingPlannerRejectsPrefixRollbackThatWouldDeleteExistingText() {
        let committed = "This is a long dictated paragraph with enough words to be well past the rollback threshold and it should be preserved"
        let resetPartial = "This is a long dictated paragraph"

        XCTAssertNil(StreamingContinuationPlanner.continuationText(
            committed: committed,
            resetTarget: resetPartial,
            maxLiveRollbackCharacters: 48
        ))
    }

    func testStreamingPlannerRejectsResetPartialAlreadyContainedInCommittedText() {
        let committed = """
        We need some R and D testing on adding custom memory to the model. Can dynamically fetch memory based on conversation and update memory based on conversation as well so I want to create this branch to test a couple things in benchmark.
        """
        let resetPartial = "Can dynamically fetch memory based on conversation and update memory based on conversation as well"

        XCTAssertNil(StreamingContinuationPlanner.continuationText(
            committed: committed,
            resetTarget: resetPartial,
            maxLiveRollbackCharacters: 48
        ))
    }

    func testStreamingPlannerRejectsResetPartialWithoutReliableOverlap() {
        let committed = "This is a long dictated paragraph with enough words to be well past the rollback threshold. Existing text should stay untouched when a reset-like partial has no suffix overlap."
        let resetPartial = "A totally different sentence from the recognizer"

        XCTAssertNil(StreamingContinuationPlanner.continuationText(
            committed: committed,
            resetTarget: resetPartial,
            maxLiveRollbackCharacters: 48
        ))
    }

    func testStreamingPlannerAppendsOnlyNewWordsAfterSuffixOverlap() {
        let committed = "This is a long dictated paragraph with enough words to be well past the rollback threshold. Can dynamically fetch memory based on conversation."
        let resetPartial = "Can dynamically fetch memory based on conversation and update memory next"

        let continuation = StreamingContinuationPlanner.continuationText(
            committed: committed,
            resetTarget: resetPartial,
            maxLiveRollbackCharacters: 48
        )

        XCTAssertEqual(continuation, " and update memory next")
    }
}
