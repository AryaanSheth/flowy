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
        // draw() renders the live "Press keys…" label while recording; here we
        // only keep the stored combo in sync with the binding.
        if !nsView.isRecording {
            nsView.title = hotkey
        }
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
    private var isHovered = false {
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
        // Let SwiftUI's frame dictate the width; only the height is fixed. A rigid
        // intrinsic width would force the hosting window to grow to fit it.
        NSSize(width: NSView.noIntrinsicMetric, height: 32)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.arrow.set()
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
        let teal = NSColor(red: 0.10, green: 0.80, blue: 0.72, alpha: 1.0)
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)

        // Match glass palette: teal tint when recording, brightening on hover.
        let bgColor: NSColor
        if isRecording {
            bgColor = teal.withAlphaComponent(0.18)
        } else if isHovered {
            bgColor = NSColor.white.withAlphaComponent(0.10)
        } else {
            bgColor = NSColor.white.withAlphaComponent(0.055)
        }
        bgColor.setFill()
        path.fill()

        let strokeColor: NSColor
        if isRecording {
            strokeColor = teal.withAlphaComponent(0.50)
        } else if isHovered {
            strokeColor = teal.withAlphaComponent(0.35)
        } else {
            strokeColor = NSColor.white.withAlphaComponent(0.09)
        }
        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        // Idle empty state reads as a call to action; otherwise show the combo.
        let display: String
        if isRecording {
            display = "Press keys…"
        } else if title.isEmpty {
            display = "Click, then press keys"
        } else {
            display = title
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let textColor = isRecording ? teal : NSColor.white
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
        ]
        let textRect = rect.insetBy(dx: 24, dy: 7)
        display.draw(in: textRect, withAttributes: attrs)

        // Pencil affordance on the right edge signals the field is editable.
        if !isRecording, let pencil = tintedSymbol(
            "pencil",
            color: NSColor.white.withAlphaComponent(isHovered ? 0.55 : 0.30),
            pointSize: 11
        ) {
            let size = pencil.size
            let origin = NSPoint(x: rect.maxX - size.width - 9, y: rect.midY - size.height / 2)
            pencil.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    private func tintedSymbol(_ name: String, color: NSColor, pointSize: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let img = NSImage(size: base.size)
        img.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: base.size)
        base.draw(in: rect)
        rect.fill(using: .sourceAtop)
        img.unlockFocus()
        return img
    }
}

enum HotkeyString {
    static func from(event: NSEvent) -> String? {
        guard let key = keyName(for: event) else { return nil }

        var parts: [String] = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Record the specific modifier pressed — not the CmdOrCtrl alias — so
        // we register exactly one Carbon hotkey instead of two (one of which
        // is often already taken by a macOS system shortcut like Ctrl+Shift+Space).
        if flags.contains(.command) { parts.append("Cmd") }
        if flags.contains(.control) { parts.append("Ctrl") }
        if flags.contains(.option)  { parts.append("Alt") }
        if flags.contains(.shift)   { parts.append("Shift") }

        guard !parts.isEmpty else { return nil }
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
