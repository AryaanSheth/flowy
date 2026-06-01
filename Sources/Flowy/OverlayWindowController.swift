import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let panel: NSPanel
    private let overlayModel = OverlayModel()
    private var hideWorkItem: DispatchWorkItem?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 88, height: 52),
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
        panel.contentView = NSHostingView(rootView: OverlayPill(model: overlayModel))
    }

    func update(status: AppStatus) {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        switch status {
        case .recording, .transcribing:
            overlayModel.status = status
            positionPanel()
            panel.orderFrontRegardless()

        case .idle:
            let item = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
            hideWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - 20
        ))
    }
}

// MARK: – Model

@MainActor
private final class OverlayModel: ObservableObject {
    @Published var status: AppStatus = .recording
}

// MARK: – Pill

private struct OverlayPill: View {
    @ObservedObject var model: OverlayModel

    private struct Bar {
        let min: CGFloat
        let max: CGFloat
        let dur: Double
        let del: Double
    }

    private let bars: [Bar] = [
        Bar(min: 3, max: 12, dur: 0.46, del: 0.00),
        Bar(min: 4, max: 18, dur: 0.38, del: 0.10),
        Bar(min: 5, max: 22, dur: 0.52, del: 0.05),
        Bar(min: 4, max: 18, dur: 0.41, del: 0.16),
        Bar(min: 3, max: 12, dur: 0.48, del: 0.08),
    ]

    @State private var heights: [CGFloat] = [3, 4, 5, 4, 3]

    var body: some View {
        HStack(spacing: 3.5) {
            ForEach(bars.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.white.opacity(model.status == .recording ? 1 : 0.55))
                    .frame(width: 2, height: heights[i])
                    .animation(.easeInOut(duration: 0.3), value: model.status)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color(white: 0.07))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 2)
        .padding(8)
        .onAppear { drive(model.status) }
        .onChange(of: model.status) { drive($0) }
    }

    private func drive(_ status: AppStatus) {
        switch status {
        case .recording:
            for (i, b) in bars.enumerated() {
                withAnimation(
                    .easeInOut(duration: b.dur)
                    .repeatForever(autoreverses: true)
                    .delay(b.del)
                ) { heights[i] = b.max }
            }

        case .transcribing:
            // Slow uniform breath — all bars together, like a pulse
            for i in bars.indices {
                withAnimation(
                    .easeInOut(duration: 1.1)
                    .repeatForever(autoreverses: true)
                    .delay(0)
                ) { heights[i] = 6 }
            }

        case .idle:
            for (i, b) in bars.enumerated() {
                withAnimation(.easeOut(duration: 0.3).delay(Double(i) * 0.03)) {
                    heights[i] = b.min
                }
            }
        }
    }
}
