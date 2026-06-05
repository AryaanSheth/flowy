import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let window: NSWindow

    init(model: AppModel) {
        self.model = model

        let content = SettingsView(model: model)
        let hostingView = NSHostingView(rootView: content)
        // Keep the window at its fixed contentRect. Without this, NSHostingView's
        // default sizing options let SwiftUI's content drive the window size, so a
        // tab containing a rigid-width NSView (the hotkey recorder) grows the window
        // each time it's shown.
        hostingView.sizingOptions = []
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Flowy"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)

        super.init()
        window.delegate = self
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
