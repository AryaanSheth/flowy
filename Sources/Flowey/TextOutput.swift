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

        switch mode {
        case .clipboard:
            copyToClipboard(text)
            return true

        case .type:
            let ok = await typeText(text, capturedApp: capturedApp)
            if !ok {
                copyToClipboard(text)
            }
            return ok

        case .typeAndClipboard:
            copyToClipboard(text)
            return await typeText(text, capturedApp: capturedApp)
        }
    }

    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func typeText(_ text: String, capturedApp: NSRunningApplication?) async -> Bool {
        if let capturedApp, !capturedApp.isTerminated {
            capturedApp.activate(options: [.activateIgnoringOtherApps])
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        copyToClipboard(text)

        if insertWithAccessibility(text) {
            return true
        }

        if await pasteClipboard() {
            return true
        }

        if typeUnicode(text) {
            return true
        }

        if !AXIsProcessTrusted() {
            showAccessibilityAlert()
        }

        return false
    }

    private static func pasteClipboard() async -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        try? await Task.sleep(nanoseconds: 80_000_000)
        return true
    }

    private static func showAccessibilityAlert() {
        guard !accessibilityAlertShown else { return }
        accessibilityAlertShown = true

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        Flowey needs Accessibility access to paste transcribed text into other apps.

        Open System Settings > Privacy & Security > Accessibility, then add or re-add Flowey. Until then, transcriptions are copied to the clipboard.
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        try? process.run()
    }

    static func requestAccessibilityAccess() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
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
        guard focusedErr == .success, let focusedRef else { return false }

        let focused = focusedRef as! AXUIElement
        let selectedErr = AXUIElementSetAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        if selectedErr == .success {
            return true
        }

        var valueRef: CFTypeRef?
        let valueErr = AXUIElementCopyAttributeValue(
            focused,
            kAXValueAttribute as CFString,
            &valueRef
        )
        guard valueErr == .success, let valueRef, CFGetTypeID(valueRef) == CFStringGetTypeID() else {
            return false
        }

        var rangeRef: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )
        guard rangeErr == .success, let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else {
            return false
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &selectedRange) else {
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
        guard setErr == .success else { return false }

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
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
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
}
