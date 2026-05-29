import SwiftUI

struct HoldRecordButton: NSViewRepresentable {
    var isRecording: Bool
    var onPress:   () -> Void
    var onRelease: () -> Void

    func makeNSView(context: Context) -> HoldRecordButtonView {
        let v = HoldRecordButtonView()
        v.onPress = onPress; v.onRelease = onRelease
        return v
    }

    func updateNSView(_ v: HoldRecordButtonView, context: Context) {
        v.isRecording = isRecording
        v.onPress = onPress; v.onRelease = onRelease
    }
}

final class HoldRecordButtonView: NSView {
    var onPress:    (() -> Void)?
    var onRelease:  (() -> Void)?
    var isRecording = false { didSet { needsDisplay = true } }
    private var mouseIsDown = false

    // Brand teal #1AAFAD
    private static let teal    = NSColor(red: 0.102, green: 0.686, blue: 0.678, alpha: 1.0)
    private static let tealDim = NSColor(red: 0.086, green: 0.580, blue: 0.573, alpha: 1.0)

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 44) }

    override func mouseDown(with event: NSEvent) {
        guard !mouseIsDown else { return }
        mouseIsDown = true
        needsDisplay = true
        onPress?()
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseIsDown else { return }
        mouseIsDown = false
        needsDisplay = true
        onRelease?()
    }

    override func mouseExited(with event: NSEvent) {
        guard mouseIsDown else { return }
        mouseIsDown = false
        needsDisplay = true
        onRelease?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)

        let fill: NSColor
        if isRecording {
            fill = NSColor.systemRed.withAlphaComponent(mouseIsDown ? 0.75 : 1.0)
        } else {
            fill = mouseIsDown ? Self.tealDim : Self.teal
        }
        fill.setFill()
        path.fill()

        // Wave bars when recording, otherwise label
        if isRecording {
            drawWaveBars(in: rect)
        } else {
            drawLabel("Hold to Record", in: rect)
        }
    }

    private func drawLabel(_ text: String, in rect: NSRect) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: para,
        ]
        text.draw(in: rect.insetBy(dx: 12, dy: 14), withAttributes: attrs)
    }

    private func drawWaveBars(in rect: NSRect) {
        let barCount = 5
        let barW: CGFloat = 3
        let maxH: CGFloat = rect.height * 0.45
        let gap: CGFloat = 5
        let total = CGFloat(barCount) * barW + CGFloat(barCount - 1) * gap
        var x = rect.midX - total / 2

        // Static wave heights (animation would require CADisplayLink)
        let phases: [CGFloat] = [0.4, 0.75, 1.0, 0.65, 0.35]
        for h in phases {
            let barH = max(4, maxH * h)
            let barRect = NSRect(x: x, y: rect.midY - barH / 2, width: barW, height: barH)
            let bp = NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5)
            NSColor.white.withAlphaComponent(0.9).setFill()
            bp.fill()
            x += barW + gap
        }
    }
}
