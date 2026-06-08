import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let panel: NSPanel
    private let overlayModel = OverlayModel()
    private var hideWorkItem: DispatchWorkItem?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 104, height: 52),
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
            if status == .transcribing {
                overlayModel.updateLevel(0)
            }
            positionPanel()
            panel.orderFrontRegardless()

        case .idle:
            overlayModel.updateLevel(0)
            let item = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
            hideWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
        }
    }

    func update(level: Double) {
        overlayModel.updateLevel(level)
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
    @Published var audioLevel: Double = 0

    private var targetLevel: Double = 0
    private var smoothingWorkItem: DispatchWorkItem?

    func updateLevel(_ rawLevel: Double) {
        let clamped = min(1, max(0, rawLevel))
        targetLevel = clamped < 0.035 ? 0 : pow((clamped - 0.035) / 0.965, 0.62)
        scheduleSmoothingTickIfNeeded()
    }

    private func scheduleSmoothingTickIfNeeded() {
        guard smoothingWorkItem == nil else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.smoothingWorkItem = nil
            self.stepSmoothedLevel()

            if abs(self.targetLevel - self.audioLevel) > 0.001 || self.audioLevel > 0.001 {
                self.scheduleSmoothingTickIfNeeded()
            }
        }
        smoothingWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 24.0, execute: item)
    }

    private func stepSmoothedLevel() {
        let smoothing = targetLevel > audioLevel ? 0.12 : 0.04
        let next = audioLevel + (targetLevel - audioLevel) * smoothing
        audioLevel = next < 0.006 && targetLevel == 0 ? 0 : next
    }
}

// MARK: – Pill

private struct OverlayPill: View {
    @ObservedObject var model: OverlayModel

    @State private var transcribingPulse = false

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(statusColor.opacity(glowOpacity))
                .frame(width: 68 + level * 10, height: 28 + level * 3)
                .blur(radius: 10)

            WaveMark(
                level: level,
                color: statusColor,
                isTranscribing: model.status == .transcribing,
                pulse: transcribingPulse
            )
            .frame(width: 64, height: 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.08),
                            Color(red: 0.02, green: 0.09, blue: 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(statusColor.opacity(model.status == .recording ? 0.38 : 0.18), lineWidth: 0.8)
                )
        )
        .shadow(color: statusColor.opacity(model.status == .recording ? 0.28 : 0.10), radius: 12, x: 0, y: 0)
        .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 2)
        .padding(8)
        .animation(.easeInOut(duration: 0.22), value: model.status)
        .onAppear { updatePulse(for: model.status) }
        .onChange(of: model.status) { updatePulse(for: $0) }
    }

    private var level: CGFloat {
        CGFloat(min(1, max(0, model.audioLevel)))
    }

    private var statusColor: Color {
        switch model.status {
        case .idle: return Color.white.opacity(0.35)
        case .recording: return Color(red: 0.10, green: 0.80, blue: 0.72)
        case .transcribing: return Color.white.opacity(0.55)
        }
    }

    private var glowOpacity: Double {
        switch model.status {
        case .recording: return 0.16 + Double(level) * 0.32
        case .transcribing: return transcribingPulse ? 0.22 : 0.08
        case .idle: return 0.04
        }
    }

    private func updatePulse(for status: AppStatus) {
        switch status {
        case .transcribing:
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                transcribingPulse = true
            }
        case .idle, .recording:
            withAnimation(.easeOut(duration: 0.2)) {
                transcribingPulse = false
            }
        }
    }
}

private struct WaveMark: View {
    let level: CGFloat
    let color: Color
    let isTranscribing: Bool
    let pulse: Bool

    @State private var startedAt = Date()

    private struct Stroke {
        let y: CGFloat
        let thickness: CGFloat
        let amplitude: CGFloat
        let opacity: Double
        let drift: CGFloat
    }

    private let strokes: [Stroke] = [
        Stroke(y: 0.28, thickness: 2.0, amplitude: 2.8, opacity: 0.46, drift: 0.30),
        Stroke(y: 0.50, thickness: 3.6, amplitude: 4.6, opacity: 0.94, drift: 0.38),
        Stroke(y: 0.72, thickness: 1.6, amplitude: 2.2, opacity: 0.38, drift: 0.24),
    ]

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
                let reactiveLevel = min(1, max(0, level))
                let transcribingLevel: CGFloat = pulse ? 0.44 : 0.18
                let drawLevel = isTranscribing ? transcribingLevel : max(0.06, reactiveLevel)
                let driftRate: CGFloat = isTranscribing ? 0.020 : (reactiveLevel > 0.025 ? 0.018 : 0)

                for (index, stroke) in strokes.enumerated() {
                    var path = Path()
                    let midY = size.height * stroke.y
                    let breath = sin(CGFloat(elapsed) * 0.10 + CGFloat(index) * 1.2)
                    let amplitude = stroke.amplitude * (0.24 + drawLevel * 1.45) * (0.94 + breath * 0.06)
                    let phase = CGFloat(elapsed) * driftRate * stroke.drift + CGFloat(index) * 0.9
                    let step: CGFloat = 2

                    path.move(to: CGPoint(x: 0, y: midY))
                    var x: CGFloat = 0
                    while x <= size.width {
                        let progress = x / max(1, size.width)
                        let wave = sin(progress * .pi * 2.0 + phase)
                        let smallerWave = sin(progress * .pi * 3.0 + phase * 0.6) * 0.08
                        let y = midY + (wave + smallerWave) * amplitude
                        path.addLine(to: CGPoint(x: x, y: y))
                        x += step
                    }

                    context.stroke(
                        path,
                        with: .color(color.opacity(stroke.opacity)),
                        style: StrokeStyle(lineWidth: stroke.thickness, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
    }
}
