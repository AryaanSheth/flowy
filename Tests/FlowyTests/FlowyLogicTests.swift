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

        let migrated = decoded.sanitized()
        XCTAssertEqual(migrated.schemaVersion, AppConfig.currentSchemaVersion)
        XCTAssertEqual(migrated.maxRecordingSecs, 300)
        XCTAssertEqual(migrated.vadSpeechThresholdDB, -45)
        XCTAssertEqual(migrated.dictionary, ["flowy": "Flowy"])
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
        XCTAssertEqual(config.ollamaModel, "llama3.2:3b")
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
}
