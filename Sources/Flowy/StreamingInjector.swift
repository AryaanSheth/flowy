import AppKit
import ApplicationServices
import Foundation

/// Types transcribed text into the focused app incrementally as partial
/// results arrive, so words appear live instead of all at once on release.
///
/// The speech recogniser revises the whole transcription on every update
/// (it can rewrite earlier words), so each update is reconciled against what
/// was already typed: the common prefix is kept, the diverging tail is
/// backspaced, and the new tail is typed. Because we only ever delete as many
/// characters as we ourselves typed, we never touch the user's own text.
///
/// Requires Accessibility (synthetic key events). When it is not granted,
/// callers should fall back to clipboard delivery instead.
@MainActor
final class StreamingInjector {
    private var committed = ""

    private let backspaceKey: CGKeyCode = 0x33  // kVK_Delete (delete to the left)
    private let returnKey:    CGKeyCode = 0x24  // kVK_Return

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
