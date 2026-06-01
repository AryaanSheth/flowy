import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var settingsController: SettingsWindowController?
    private var overlayController: OverlayWindowController?
    private var hotkeyMonitor: HotkeyMonitor?
    private var allowQuit = false
    // Held alive so the SwiftUI translation task stays active (macOS 14+)
    private var translationBridge: AnyObject?
    private var translationWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FlowyLog.info("App launched bundle=\(Bundle.main.bundlePath) pid=\(ProcessInfo.processInfo.processIdentifier)")
        NSApp.setActivationPolicy(.accessory)

        settingsController = SettingsWindowController(model: model)
        overlayController = OverlayWindowController()
        buildStatusItem()

        model.onStatusChanged = { [weak self] status in
            self?.applyStatus(status)
        }
        model.onHotkeyChanged = { [weak self] hotkey in
            self?.installHotkey(hotkey)
        }

        setupTranslation()

        model.requestInitialPermissions()
        installHotkey(model.config.hotkey)
        settingsController?.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        allowQuit ? .terminateNow : .terminateCancel
    }

    private func setupTranslation() {
        guard #available(macOS 15, *) else { return }
        let bridge = TranslationBridge()
        let hostView = NSHostingView(rootView: TranslationBackgroundView(bridge: bridge))
        hostView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.contentView = hostView
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .transient]
        win.setFrameOrigin(NSPoint(x: -1000, y: -1000))
        win.orderFrontRegardless()

        translationBridge = bridge
        translationWindow = win

        model.translateText = { [weak bridge] text, targetBCP47 in
            guard let bridge else { return text }
            return try await bridge.translate(text, targetLanguageBCP47: targetBCP47)
        }
        FlowyLog.info("Translation bridge installed")
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        item.button?.target = self
        item.button?.action = #selector(openSettings)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Start Recording", action: #selector(startRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Flowy", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        item.menu = menu

        applyStatus(model.status)
    }

    private func installHotkey(_ hotkey: String) {
        do {
            if hotkeyMonitor == nil {
                hotkeyMonitor = try HotkeyMonitor(hotkey: hotkey)
                hotkeyMonitor?.onStart = { [weak self] in self?.model.startRecording() }
                hotkeyMonitor?.onStop = { [weak self] in self?.model.stopRecording() }
                try hotkeyMonitor?.start()
            } else {
                try hotkeyMonitor?.update(hotkey: hotkey)
            }
        } catch {
            model.lastError = error.localizedDescription
            FlowyLog.error("Hotkey setup failed: \(error.localizedDescription)")
            NSLog("Hotkey setup failed: \(error.localizedDescription)")
        }
    }

    private func applyStatus(_ status: AppStatus) {
        let image = NSImage(systemSymbolName: status.systemImageName, accessibilityDescription: status.label)
        image?.isTemplate = status != .recording
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = "Flowy - \(status.label)"
        overlayController?.update(status: status)
    }

    @objc private func openSettings() {
        settingsController?.show()
    }

    @objc private func startRecording() {
        model.startRecording()
    }

    @objc private func stopRecording() {
        model.stopRecording()
    }

    @objc private func quit() {
        allowQuit = true
        NSApp.terminate(nil)
    }
}
