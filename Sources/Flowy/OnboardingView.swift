import AppKit
import AVFoundation
import Speech
import SwiftUI

// MARK: – Shared primitives (scoped to this file)

private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

private enum G {
    static let text   = Color.white
    static let dim    = Color.white.opacity(0.48)
    static let faint  = Color.white.opacity(0.22)
    static let border = Color.white.opacity(0.09)
    static let fill   = Color.white.opacity(0.055)
    static let teal   = Color(red: 0.10, green: 0.80, blue: 0.72)
}

private struct PrimaryBtn: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 28).padding(.vertical, 9)
            .background(
                G.teal.opacity(configuration.isPressed ? 0.7 : 1),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

// MARK: – Main view

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var onComplete: () -> Void

    @State private var stepIndex = 0
    // steps: 0=welcome, 1=speech, 2=microphone, 3=accessibility, 4=done

    private let pollTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            VisualEffect(material: .hudWindow, blending: .behindWindow)
                .ignoresSafeArea()
            Color(red: 0.08, green: 0.09, blue: 0.10).opacity(0.82)
                .ignoresSafeArea()

            Group {
                switch stepIndex {
                case 0:  welcomeScreen
                case 4:  doneScreen
                default: permissionScreen(stepIndex)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            ))
            .id(stepIndex)
        }
        .environment(\.colorScheme, .dark)
        .frame(width: 440, height: 480)
        .onReceive(pollTimer) { _ in
            model.refreshPermissions()
            autoAdvanceIfGranted()
        }
    }

    // MARK: – Screens

    private var welcomeScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            waveLogo
                .padding(.bottom, 22)

            Text("Welcome to flowy")
                .font(.system(size: 22, weight: .semibold, design: .default))
                .foregroundStyle(G.text)
                .tracking(-0.4)
                .padding(.bottom, 10)

            Text("Dictate anywhere on your Mac.\nLocal, private, instant.")
                .font(.system(size: 13))
                .foregroundStyle(G.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.bottom, 44)

            Button("Get Started") {
                withAnimation(.easeInOut(duration: 0.22)) { stepIndex = 1 }
            }
            .buttonStyle(PrimaryBtn())
            .padding(.bottom, 14)

            Text("Takes about 30 seconds")
                .font(.system(size: 11))
                .foregroundStyle(G.faint)

            Spacer()
        }
        .padding(.horizontal, 48)
    }

    private func permissionScreen(_ step: Int) -> some View {
        let info = permInfo(step)
        let granted = isGranted(step)

        return VStack(spacing: 0) {
            progressDots
                .padding(.top, 32)

            Spacer()

            Image(systemName: info.icon)
                .font(.system(size: 38, weight: .thin))
                .foregroundStyle(granted ? G.teal : G.dim)
                .padding(.bottom, 20)

            Text(info.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(G.text)
                .tracking(-0.3)
                .padding(.bottom, 8)

            Text(info.description)
                .font(.system(size: 12))
                .foregroundStyle(G.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 300)
                .padding(.bottom, 32)

            if granted {
                grantedBadge
                    .padding(.bottom, 24)
                Button("Continue") {
                    withAnimation(.easeInOut(duration: 0.22)) { stepIndex += 1 }
                }
                .buttonStyle(PrimaryBtn())
            } else {
                Spacer().frame(height: 34 + 24)  // mirror badge + margin height
                Button(info.actionLabel) { grantAction(step) }
                    .buttonStyle(PrimaryBtn())
                if step == 3 {
                    Button("Skip for now") {
                        withAnimation(.easeInOut(duration: 0.22)) { stepIndex = 4 }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(G.faint)
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 48)
    }

    private var doneScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38, weight: .thin))
                .foregroundStyle(G.teal)
                .padding(.bottom, 14)

            Text("You're all set!")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(G.text)
                .tracking(-0.4)
                .padding(.bottom, 18)

            // Where to find Flowy — it has no dock icon and no window.
            menuBarHint
                .padding(.bottom, 18)

            // How to dictate, as numbered steps.
            VStack(alignment: .leading, spacing: 12) {
                usageStep(1) {
                    HStack(spacing: 6) {
                        Text("Press").foregroundStyle(G.dim)
                        hotkeyDisplay
                    }
                }
                usageStep(2) {
                    Text("Speak — text appears at your cursor")
                        .foregroundStyle(G.dim)
                }
                usageStep(3) {
                    Text("Press again to stop (or hold, then release)")
                        .foregroundStyle(G.dim)
                }
            }
            .font(.system(size: 12))
            .padding(.bottom, 26)

            Button("Open Settings") { onComplete() }
                .buttonStyle(PrimaryBtn())

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: – Reusable bits

    private var waveLogo: some View {
        Canvas { ctx, size in
            var p = Path()
            let h = size.height, w = size.width
            p.move(to: .init(x: 0, y: h * 0.5))
            p.addCurve(to: .init(x: w * 0.5, y: h * 0.5),
                       control1: .init(x: w * 0.15, y: h * 0.1),
                       control2: .init(x: w * 0.35, y: h * 0.9))
            p.addCurve(to: .init(x: w, y: h * 0.5),
                       control1: .init(x: w * 0.65, y: h * 0.1),
                       control2: .init(x: w * 0.85, y: h * 0.9))
            ctx.stroke(p, with: .color(G.teal),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(width: 52, height: 28)
    }

    private var grantedBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(G.teal).frame(width: 6, height: 6)
            Text("Access granted")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(G.teal)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(G.teal.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(G.teal.opacity(0.18), lineWidth: 1))
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { i in
                Capsule()
                    .fill(i == stepIndex ? G.teal : G.border)
                    .frame(width: i == stepIndex ? 22 : 6, height: 6)
            }
        }
        .animation(.spring(duration: 0.3), value: stepIndex)
    }

    private var hotkeyDisplay: some View {
        HStack(spacing: 6) {
            ForEach(formattedHotkey, id: \.self) { key in
                Text(key)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(G.text)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(G.fill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(G.border, lineWidth: 1))
            }
        }
    }

    // Shows a faux menu bar so the user knows Flowy lives in the top-right
    // status area — there is no dock icon and no main window.
    private var menuBarHint: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(G.fill)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(G.border, lineWidth: 1))
                    .frame(height: 28)
                    .overlay(alignment: .trailing) {
                        HStack(spacing: 14) {
                            Image(systemName: "wifi")
                            Image(systemName: "battery.75")
                            Image(systemName: "magnifyingglass")
                            // Flowy's icon, ringed to draw the eye.
                            waveLogo
                                .frame(width: 18, height: 11)
                                .padding(5)
                                .background(G.teal.opacity(0.14), in: Circle())
                                .overlay(Circle().strokeBorder(G.teal.opacity(0.5), lineWidth: 1))
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(G.faint)
                        .padding(.trailing, 8)
                    }
            }

            Text("Flowy lives in your menu bar — top-right.\nNo dock icon; it runs quietly in the background.")
                .font(.system(size: 12))
                .foregroundStyle(G.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    private func usageStep<C: View>(_ n: Int, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(G.teal)
                .frame(width: 20, height: 20)
                .background(G.teal.opacity(0.12), in: Circle())
            content()
            Spacer(minLength: 0)
        }
    }

    // MARK: – Data helpers

    private struct PermInfo {
        let icon: String
        let title: String
        let description: String
        let actionLabel: String
    }

    private func permInfo(_ step: Int) -> PermInfo {
        switch step {
        case 1: return PermInfo(
            icon: "waveform",
            title: "Speech Recognition",
            description: "Flowy uses macOS's on-device engine — your voice is never sent to a server.",
            actionLabel: "Grant Access"
        )
        case 2: return PermInfo(
            icon: "mic",
            title: "Microphone",
            description: "To hear you speak, Flowy needs access to your microphone.",
            actionLabel: "Grant Access"
        )
        case 3: return PermInfo(
            icon: "keyboard",
            title: "Accessibility",
            description: "To type transcribed text into any app, Flowy needs Accessibility. Without it, text goes to clipboard only.",
            actionLabel: "Open Settings"
        )
        default: return PermInfo(icon: "", title: "", description: "", actionLabel: "")
        }
    }

    private func isGranted(_ step: Int) -> Bool {
        switch step {
        case 1: return model.permissions.speechAuthorized
        case 2: return model.permissions.microphoneAuthorized
        case 3: return model.permissions.accessibilityTrusted
        default: return false
        }
    }

    private func grantAction(_ step: Int) {
        switch step {
        case 1:
            SFSpeechRecognizer.requestAuthorization { _ in
                DispatchQueue.main.async { model.refreshPermissions() }
            }
        case 2:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { model.refreshPermissions() }
            }
        case 3:
            TextOutput.requestAccessibilityAccess()
            TextOutput.openAccessibilitySettings()
        default:
            break
        }
    }

    private func autoAdvanceIfGranted() {
        // Auto-advance speech and mic only — accessibility needs manual confirm
        guard stepIndex == 1 || stepIndex == 2 else { return }
        if isGranted(stepIndex) {
            withAnimation(.easeInOut(duration: 0.22)) { stepIndex += 1 }
        }
    }

    private var formattedHotkey: [String] {
        model.config.hotkey.split(separator: "+").map { part in
            switch part.lowercased() {
            case "cmdorctrl", "cmd", "command": return "⌘"
            case "shift":                        return "⇧"
            case "alt", "option":               return "⌥"
            case "ctrl", "control":             return "⌃"
            case "space":                       return "Space"
            default:                            return String(part)
            }
        }
    }
}
