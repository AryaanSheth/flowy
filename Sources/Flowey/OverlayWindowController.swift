import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let panel: NSPanel
    private var hideWorkItem: DispatchWorkItem?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 230, height: 62),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: OverlayPill(status: .recording))
    }

    func update(status: AppStatus) {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        switch status {
        case .recording, .transcribing:
            panel.contentView = NSHostingView(rootView: OverlayPill(status: status))
            positionPanel()
            panel.orderFrontRegardless()

        case .idle:
            let item = DispatchWorkItem { [weak panel] in
                panel?.orderOut(nil)
            }
            hideWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height - 28
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct OverlayPill: View {
    let status: AppStatus

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(status == .recording ? Color.red : Color.accentColor)
                .frame(width: 10, height: 10)
            Text(status == .recording ? "Recording..." : "Processing...")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            if status == .transcribing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(width: 230, height: 62)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .padding(4)
    }
}
