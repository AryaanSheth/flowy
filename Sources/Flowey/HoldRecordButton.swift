import SwiftUI

struct HoldRecordButton: NSViewRepresentable {
    var isRecording: Bool
    var onPress: () -> Void
    var onRelease: () -> Void

    func makeNSView(context: Context) -> HoldRecordButtonView {
        let view = HoldRecordButtonView()
        view.onPress = onPress
        view.onRelease = onRelease
        return view
    }

    func updateNSView(_ nsView: HoldRecordButtonView, context: Context) {
        nsView.isRecording = isRecording
        nsView.onPress = onPress
        nsView.onRelease = onRelease
    }
}

final class HoldRecordButtonView: NSView {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var isRecording = false {
        didSet { needsDisplay = true }
    }
    private var mouseIsDown = false

    override var intrinsicContentSize: NSSize {
        NSSize(width: 210, height: 44)
    }

    override func mouseDown(with event: NSEvent) {
        guard !mouseIsDown else { return }
        mouseIsDown = true
        onPress?()
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseIsDown else { return }
        mouseIsDown = false
        onRelease?()
    }

    override func mouseExited(with event: NSEvent) {
        guard mouseIsDown else { return }
        mouseIsDown = false
        onRelease?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        ))
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        let fill = isRecording ? NSColor.systemRed : NSColor.controlAccentColor
        fill.setFill()
        path.fill()

        let label = isRecording ? "Recording..." : "Hold to Record"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        label.draw(in: rect.insetBy(dx: 12, dy: 13), withAttributes: attrs)
    }
}
