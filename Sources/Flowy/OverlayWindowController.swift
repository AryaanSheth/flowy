import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let panel: NSPanel
    private let overlayModel = OverlayModel()
    private var hideWorkItem: DispatchWorkItem?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 230, height: 86),
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - 24
        ))
    }
}

// MARK: – Observable model

@MainActor
private final class OverlayModel: ObservableObject {
    @Published var status: AppStatus = .recording
}

// MARK: – Waveform overlay pill

private struct OverlayPill: View {
    @ObservedObject var model: OverlayModel

    private struct Bar {
        let minH: CGFloat
        let maxH: CGFloat
        let duration: Double
        let delay: Double
    }

    private let bars: [Bar] = [
        Bar(minH: 4,  maxH: 18, duration: 0.44, delay: 0.00),
        Bar(minH: 6,  maxH: 26, duration: 0.36, delay: 0.13),
        Bar(minH: 10, maxH: 32, duration: 0.50, delay: 0.06),
        Bar(minH: 6,  maxH: 26, duration: 0.39, delay: 0.20),
        Bar(minH: 4,  maxH: 18, duration: 0.42, delay: 0.10),
    ]

    @State private var heights: [CGFloat] = [4, 6, 10, 6, 4]

    var body: some View {
        ZStack {
            // Outer dark container with blue glow border
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(white: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.25, green: 0.55, blue: 1.00),
                                    Color(red: 0.20, green: 0.45, blue: 0.95),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.5
                        )
                )
                .shadow(color: Color(red: 0.25, green: 0.55, blue: 1.0).opacity(0.55),
                        radius: 10, x: 0, y: 0)
                .frame(width: 202, height: 66)

            // Inner dark pill
            Capsule(style: .continuous)
                .fill(Color(white: 0.14))
                .frame(width: 116, height: 42)
                .overlay(waveform)
        }
        // Panel is 230×86; extra room lets the shadow render without clipping
        .frame(width: 230, height: 86)
        .onAppear { animate(model.status) }
        .onChange(of: model.status) { animate($0) }
    }

    private var waveform: some View {
        HStack(spacing: 4.5) {
            ForEach(bars.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(.white)
                    .frame(width: 3.5, height: heights[i])
            }
        }
    }

    private func animate(_ status: AppStatus) {
        if status == .recording {
            for (i, bar) in bars.enumerated() {
                withAnimation(
                    Animation
                        .easeInOut(duration: bar.duration)
                        .repeatForever(autoreverses: true)
                        .delay(bar.delay)
                ) {
                    heights[i] = bar.maxH
                }
            }
        } else {
            // Bars settle gently when processing / idle
            for (i, bar) in bars.enumerated() {
                withAnimation(
                    .easeOut(duration: 0.45).delay(Double(i) * 0.04)
                ) {
                    heights[i] = bar.minH
                }
            }
        }
    }
}
