import Carbon
import SwiftUI

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var hotkey: String

    func makeNSView(context: Context) -> RecorderButton {
        let view = RecorderButton()
        view.onHotkey = { hotkey in
            self.hotkey = hotkey
        }
        view.title = hotkey
        return view
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.title = nsView.isRecording ? "Press shortcut..." : hotkey
    }
}

final class RecorderButton: NSView {
    var onHotkey: ((String) -> Void)?
    var isRecording = false {
        didSet {
            needsDisplay = true
            if isRecording {
                window?.makeFirstResponder(self)
            }
        }
    }
    var title = "" {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 250, height: 32)
    }

    override func mouseDown(with event: NSEvent) {
        isRecording.toggle()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        guard let combo = HotkeyString.from(event: event) else {
            NSSound.beep()
            return
        }

        isRecording = false
        title = combo
        onHotkey?(combo)
    }

    override func cancelOperation(_ sender: Any?) {
        isRecording = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        let background = isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.16) : NSColor.controlBackgroundColor
        background.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let display = title.isEmpty ? "Record shortcut" : title
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let textRect = rect.insetBy(dx: 10, dy: 7)
        display.draw(in: textRect, withAttributes: attrs)
    }
}

enum HotkeyString {
    static func from(event: NSEvent) -> String? {
        guard let key = keyName(for: event) else { return nil }

        var parts: [String] = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) {
            parts.append("CmdOrCtrl")
        }
        if flags.contains(.option) {
            parts.append("Alt")
        }
        if flags.contains(.shift) {
            parts.append("Shift")
        }

        parts.append(key)
        return parts.joined(separator: "+")
    }

    private static func keyName(for event: NSEvent) -> String? {
        let keyCode = Int(event.keyCode)
        if let named = keyNames[keyCode] {
            return named
        }

        if let chars = event.charactersIgnoringModifiers, chars.count == 1 {
            let char = chars.uppercased()
            if char.rangeOfCharacter(from: CharacterSet.alphanumerics) != nil {
                return char
            }
        }

        return nil
    }

    private static let keyNames: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "Return",
        kVK_Tab: "Tab",
        kVK_Escape: "Escape",
        kVK_Delete: "Delete",
        kVK_LeftArrow: "Left",
        kVK_RightArrow: "Right",
        kVK_UpArrow: "Up",
        kVK_DownArrow: "Down",
        kVK_F1: "F1",
        kVK_F2: "F2",
        kVK_F3: "F3",
        kVK_F4: "F4",
        kVK_F5: "F5",
        kVK_F6: "F6",
        kVK_F7: "F7",
        kVK_F8: "F8",
        kVK_F9: "F9",
        kVK_F10: "F10",
        kVK_F11: "F11",
        kVK_F12: "F12",
        kVK_F13: "F13",
        kVK_F14: "F14",
        kVK_F15: "F15",
        kVK_F16: "F16",
        kVK_F17: "F17",
        kVK_F18: "F18",
        kVK_F19: "F19",
        kVK_F20: "F20",
    ]
}
