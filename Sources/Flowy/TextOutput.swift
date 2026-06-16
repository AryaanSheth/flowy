import AppKit
import ApplicationServices
import Foundation

@MainActor
enum TextOutput {
    private static var accessibilityAlertShown = false
    private static let vKeyCode: CGKeyCode = 0x09

    @discardableResult
    static func deliver(_ text: String, mode: OutputMode, capturedApp: NSRunningApplication?) async -> Bool {
        guard !text.isEmpty else { return true }
        FlowyLog.info("Delivery start mode=\(mode.rawValue) chars=\(text.count) capturedApp=\(capturedApp?.localizedName ?? "none") trusted=\(AXIsProcessTrusted())")

        switch mode {
        case .clipboard:
            let ok = copyToClipboard(text)
            FlowyLog.info("Delivery clipboard-only copy ok=\(ok)")
            return ok

        case .type:
            let ok = await typeText(text, capturedApp: capturedApp, preserveClipboard: true)
            if !ok {
                copyToClipboard(text)
            }
            return ok

        case .typeAndClipboard:
            copyToClipboard(text)
            return await typeText(text, capturedApp: capturedApp, preserveClipboard: false)
        }
    }

    @discardableResult
    static func copyToClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let ok = pasteboard.setString(text, forType: .string)
        FlowyLog.info("Clipboard write ok=\(ok) chars=\(text.count)")
        return ok
    }

    private static func typeText(
        _ text: String,
        capturedApp: NSRunningApplication?,
        preserveClipboard: Bool
    ) async -> Bool {
        if let capturedApp, !capturedApp.isTerminated {
            let alreadyFront = NSWorkspace.shared.frontmostApplication?
                .processIdentifier == capturedApp.processIdentifier
            if !alreadyFront {
                FlowyLog.info("Reactivating captured app name=\(capturedApp.localizedName ?? "unknown")")
                capturedApp.activate(options: [.activateIgnoringOtherApps])
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        } else {
            FlowyLog.warn("No captured app available for delivery")
        }

        let snapshot = preserveClipboard ? PasteboardSnapshot.capture() : nil
        guard copyToClipboard(text) else {
            FlowyLog.error("Delivery failed: clipboard write failed")
            return false
        }
        let copiedChangeCount = NSPasteboard.general.changeCount

        if pasteClipboard() {
            FlowyLog.info("Delivery attempted via Cmd+V")
            await restoreClipboard(snapshot, copiedChangeCount: copiedChangeCount)
            return true
        }

        if insertWithAccessibility(text) {
            FlowyLog.info("Delivery succeeded via AX insertion")
            await restoreClipboard(snapshot, copiedChangeCount: copiedChangeCount)
            return true
        }

        if typeUnicode(text) {
            FlowyLog.info("Delivery succeeded via Unicode typing")
            await restoreClipboard(snapshot, copiedChangeCount: copiedChangeCount)
            return true
        }

        if !AXIsProcessTrusted() {
            showAccessibilityAlert()
        }

        await restoreClipboard(snapshot, copiedChangeCount: copiedChangeCount)
        return false
    }

    private static func restoreClipboard(
        _ snapshot: PasteboardSnapshot?,
        copiedChangeCount: Int
    ) async {
        guard let snapshot else { return }

        try? await Task.sleep(nanoseconds: 120_000_000)
        snapshot.restoreIfUnchanged(since: copiedChangeCount)
    }

    private static func pasteClipboard() -> Bool {
        guard AXIsProcessTrusted() else {
            FlowyLog.warn("Cmd+V skipped: AXIsProcessTrusted=false, macOS will ignore synthetic paste events")
            return false
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            FlowyLog.error("Cmd+V failed: could not create CGEventSource")
            return false
        }

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            FlowyLog.error("Cmd+V failed: could not create keyboard events")
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        return true
    }

    private static func showAccessibilityAlert() {
        guard !accessibilityAlertShown else { return }
        accessibilityAlertShown = true

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        Flowy needs Accessibility access to paste transcribed text into other apps.

        Open System Settings > Privacy & Security > Accessibility and add Flowy. \
        If Flowy is already listed with the switch ON, remove it and re-add it — \
        macOS invalidates the trust each time the app is rebuilt. \
        Until then, transcriptions are copied to the clipboard only.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            requestAccessibilityAccess()
            openAccessibilitySettings()
        }
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    static func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func insertWithAccessibility(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedErr = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusedErr == .success, let focusedRef else {
            FlowyLog.warn("AX insert failed: focused element error=\(focusedErr.rawValue)")
            return false
        }

        let focused = focusedRef as! AXUIElement
        let selectedErr = AXUIElementSetAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        if selectedErr == .success {
            return true
        }
        FlowyLog.warn("AX selected-text insert failed error=\(selectedErr.rawValue)")

        var valueRef: CFTypeRef?
        let valueErr = AXUIElementCopyAttributeValue(
            focused,
            kAXValueAttribute as CFString,
            &valueRef
        )
        guard valueErr == .success, let valueRef, CFGetTypeID(valueRef) == CFStringGetTypeID() else {
            FlowyLog.warn("AX value read failed error=\(valueErr.rawValue)")
            return false
        }

        var rangeRef: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )
        guard rangeErr == .success, let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else {
            FlowyLog.warn("AX selected range read failed error=\(rangeErr.rawValue)")
            return false
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &selectedRange) else {
            FlowyLog.warn("AX selected range decode failed")
            return false
        }

        let currentValue = valueRef as! String
        let mutable = NSMutableString(string: currentValue)
        let currentLength = mutable.length
        let location = min(max(selectedRange.location, 0), currentLength)
        let length = min(max(selectedRange.length, 0), currentLength - location)

        mutable.replaceCharacters(in: NSRange(location: location, length: length), with: text)
        let setErr = AXUIElementSetAttributeValue(
            focused,
            kAXValueAttribute as CFString,
            mutable as CFString
        )
        guard setErr == .success else {
            FlowyLog.warn("AX value write failed error=\(setErr.rawValue)")
            return false
        }

        var nextRange = CFRange(location: location + (text as NSString).length, length: 0)
        if let nextRangeValue = AXValueCreate(.cfRange, &nextRange) {
            AXUIElementSetAttributeValue(
                focused,
                kAXSelectedTextRangeAttribute as CFString,
                nextRangeValue
            )
        }

        return true
    }

    private static func typeUnicode(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else {
            FlowyLog.warn("Unicode typing skipped: AXIsProcessTrusted=false, macOS will ignore synthetic key events")
            return false
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            FlowyLog.error("Unicode typing failed: could not create CGEventSource")
            return false
        }

        let nsText = text as NSString
        var offset = 0
        while offset < nsText.length {
            let chunkLength = min(20, nsText.length - offset)
            var chars = [UniChar](repeating: 0, count: chunkLength)
            nsText.getCharacters(&chars, range: NSRange(location: offset, length: chunkLength))

            guard
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                FlowyLog.error("Unicode typing failed: could not create keyboard events")
                return false
            }

            chars.withUnsafeBufferPointer { buffer in
                keyDown.keyboardSetUnicodeString(stringLength: chunkLength, unicodeString: buffer.baseAddress)
            }
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)

            offset += chunkLength
            Thread.sleep(forTimeInterval: 0.005)
        }

        return true
    }

    private struct PasteboardSnapshot {
        let items: [NSPasteboardItem]

        static func capture() -> PasteboardSnapshot {
            let copiedItems = NSPasteboard.general.pasteboardItems?.compactMap {
                $0.copy() as? NSPasteboardItem
            } ?? []
            return PasteboardSnapshot(items: copiedItems)
        }

        func restoreIfUnchanged(since changeCount: Int) {
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == changeCount else {
                FlowyLog.info("Clipboard restore skipped because pasteboard changed")
                return
            }

            pasteboard.clearContents()
            if !items.isEmpty {
                pasteboard.writeObjects(items)
            }
            FlowyLog.info("Clipboard restored after inject-only delivery")
        }
    }
}
