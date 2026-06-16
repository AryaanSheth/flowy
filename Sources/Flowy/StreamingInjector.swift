import AppKit
import ApplicationServices
import Foundation

/// Types transcribed text into the focused app incrementally as partial
/// results arrive, so words appear live instead of all at once on release.
///
/// The speech recogniser usually revises the whole transcription on every
/// update, but it can occasionally restart and emit only the latest phrase.
/// Small revisions are reconciled with backspaces; large rollbacks are treated
/// as recogniser resets and handled append-only so a bad partial cannot wipe a
/// long dictation.
///
/// Requires Accessibility (synthetic key events). When it is not granted,
/// callers should fall back to clipboard delivery instead.
@MainActor
final class StreamingInjector {
    private var committed = ""

    private let backspaceKey: CGKeyCode = 0x33  // kVK_Delete (delete to the left)
    private let returnKey:    CGKeyCode = 0x24  // kVK_Return
    private let maxLiveRollbackCharacters = 48

    /// True once any text has been typed for the current recording.
    var isActive: Bool { !committed.isEmpty }

    /// The text currently present in the target app from this injector.
    var committedText: String { committed }

    /// Begin a fresh recording. Drops the committed state without touching the app.
    func reset() {
        committed = ""
    }

    /// Reconcile the target app to `target`, typing/backspacing the difference.
    @discardableResult
    func update(to target: String) -> Bool {
        guard target != committed else { return true }
        guard AXIsProcessTrusted() else { return false }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }

        let old = Array(committed)
        let new = Array(target)

        var common = 0
        let limit = min(old.count, new.count)
        while common < limit && old[common] == new[common] { common += 1 }

        let deletions = old.count - common
        if StreamingContinuationPlanner.isUnsafeRollback(
            deletions: deletions,
            oldCount: old.count,
            newCount: new.count,
            commonPrefix: common,
            maxLiveRollbackCharacters: maxLiveRollbackCharacters
        ) {
            guard let continuation = StreamingContinuationPlanner.continuationText(
                committed: committed,
                resetTarget: target,
                maxLiveRollbackCharacters: maxLiveRollbackCharacters
            ) else {
                FlowyLog.warn("StreamingInjector ignored reset-like partial old=\(old.count) new=\(new.count) common=\(common)")
                return true
            }

            typeRun(continuation, source: source)
            committed += continuation
            FlowyLog.warn("StreamingInjector converted reset-like partial to append old=\(old.count) new=\(new.count) appended=\(Array(continuation).count)")
            return true
        }

        if deletions > 0 {
            sendBackspaces(deletions, source: source)
        }

        if common < new.count {
            typeRun(String(new[common...]), source: source)
        }

        committed = target
        return true
    }

    // MARK: – Low-level posting

    private func sendBackspaces(_ count: Int, source: CGEventSource) {
        for _ in 0..<count {
            CGEvent(keyboardEventSource: source, virtualKey: backspaceKey, keyDown: true)?
                .post(tap: .cgSessionEventTap)
            CGEvent(keyboardEventSource: source, virtualKey: backspaceKey, keyDown: false)?
                .post(tap: .cgSessionEventTap)
            Thread.sleep(forTimeInterval: 0.0006)
        }
    }

    private func typeRun(_ text: String, source: CGEventSource) {
        // Split on newlines so line breaks are sent as real Return keystrokes,
        // which every app honours (a Unicode \n via setUnicodeString does not).
        let segments = text.components(separatedBy: "\n")
        for (index, segment) in segments.enumerated() {
            if index > 0 { sendReturn(source: source) }
            if !segment.isEmpty { typeUnicode(segment, source: source) }
        }
    }

    private func sendReturn(source: CGEventSource) {
        CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true)?
            .post(tap: .cgSessionEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false)?
            .post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.0006)
    }

    private func typeUnicode(_ text: String, source: CGEventSource) {
        let ns = text as NSString
        var offset = 0
        while offset < ns.length {
            let chunkLength = min(20, ns.length - offset)
            var chars = [UniChar](repeating: 0, count: chunkLength)
            ns.getCharacters(&chars, range: NSRange(location: offset, length: chunkLength))

            guard
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { return }

            chars.withUnsafeBufferPointer { buffer in
                keyDown.keyboardSetUnicodeString(stringLength: chunkLength, unicodeString: buffer.baseAddress)
                keyUp.keyboardSetUnicodeString(stringLength: chunkLength, unicodeString: buffer.baseAddress)
            }
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)

            offset += chunkLength
            Thread.sleep(forTimeInterval: 0.0006)
        }
    }
}

enum StreamingContinuationPlanner {
    static func isUnsafeRollback(
        deletions: Int,
        oldCount: Int,
        newCount: Int,
        commonPrefix: Int,
        maxLiveRollbackCharacters: Int
    ) -> Bool {
        guard deletions > maxLiveRollbackCharacters else { return false }

        let oldIsLong = oldCount > maxLiveRollbackCharacters * 2
        let lostMostOfTypedText = newCount < oldCount - maxLiveRollbackCharacters
        let weakSharedPrefix = commonPrefix < min(24, oldCount / 4)

        return oldIsLong && (lostMostOfTypedText || weakSharedPrefix)
    }

    static func continuationText(
        committed: String,
        resetTarget: String,
        maxLiveRollbackCharacters: Int
    ) -> String? {
        let target = resetTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }

        let committedLower = committed.lowercased()
        let targetLower = target.lowercased()
        let committedTokens = wordTokens(in: committed)
        let targetTokens = wordTokens(in: target)

        if committedLower.hasPrefix(targetLower) {
            return nil
        }

        guard !targetTokens.isEmpty else { return nil }

        if containsWordSequence(
            committedTokens.map(\.normalized),
            targetTokens.map(\.normalized)
        ) {
            return nil
        }

        guard Array(targetLower).count < Array(committedLower).count - maxLiveRollbackCharacters else {
            return nil
        }

        guard let overlap = suffixPrefixOverlap(committedTokens, targetTokens) else {
            return nil
        }

        let minimumOverlap = min(5, max(2, targetTokens.count / 4))
        guard overlap.wordCount >= minimumOverlap else {
            return nil
        }

        let tail = String(target[overlap.targetEndIndex...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else { return nil }

        return separator(beforeAppending: tail, to: committed) + tail
    }

    private struct WordToken {
        let normalized: String
        let endIndex: String.Index
    }

    private struct WordOverlap {
        let wordCount: Int
        let targetEndIndex: String.Index
    }

    private static func wordTokens(in text: String) -> [WordToken] {
        var tokens: [WordToken] = []
        var current = ""
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if isWordCharacter(character) {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(WordToken(normalized: current.lowercased(), endIndex: index))
                current = ""
            }
            index = text.index(after: index)
        }

        if !current.isEmpty {
            tokens.append(WordToken(normalized: current.lowercased(), endIndex: text.endIndex))
        }

        return tokens
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    private static func containsWordSequence(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }

        for start in 0...(haystack.count - needle.count) {
            var matches = true
            for offset in 0..<needle.count where haystack[start + offset] != needle[offset] {
                matches = false
                break
            }
            if matches { return true }
        }

        return false
    }

    private static func suffixPrefixOverlap(_ lhs: [WordToken], _ rhs: [WordToken]) -> WordOverlap? {
        guard !lhs.isEmpty, !rhs.isEmpty else { return nil }

        let maxOverlap = min(lhs.count, rhs.count, 40)
        guard maxOverlap > 0 else { return nil }

        for length in stride(from: maxOverlap, through: 1, by: -1) {
            let leftStart = lhs.count - length
            var matches = true
            for i in 0..<length where lhs[leftStart + i].normalized != rhs[i].normalized {
                matches = false
                break
            }
            if matches {
                return WordOverlap(wordCount: length, targetEndIndex: rhs[length - 1].endIndex)
            }
        }

        return nil
    }

    private static func separator(beforeAppending tail: String, to committed: String) -> String {
        guard let last = committed.unicodeScalars.last else { return "" }
        guard let first = tail.unicodeScalars.first else { return "" }

        if CharacterSet.whitespacesAndNewlines.contains(last) {
            return ""
        }
        if CharacterSet.punctuationCharacters.contains(first) {
            return ""
        }
        return " "
    }
}
