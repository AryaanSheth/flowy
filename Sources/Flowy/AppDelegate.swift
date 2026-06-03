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
    private var onboardingController: OnboardingWindowController?
    // Held alive so the SwiftUI translation task stays active (macOS 14+)
    private var translationBridge: AnyObject?
    private var translationWindow: NSWindow?

    private static let setupCompletedKey = "hasCompletedSetup"
    private static let hotkeySeededKey   = "hasSeededHotkey"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bootstrap Swift concurrency runtime before any UI interaction.
        // On macOS 26 beta, MainActor.assumeIsolated (called by SwiftUI on every
        // button press) crashes with EXC_BAD_ACCESS if the runtime hasn't been
        // initialized — the executor ref reads as 0x1e instead of a valid pointer.
        Task { @MainActor in }

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
        observeSystemSettings()

        model.requestInitialPermissions()

        // Defer hotkey installation to the next run loop cycle.
        // RegisterEventHotKey called during applicationDidFinishLaunching (before
        // the run loop's first iteration) produces a silent no-op on macOS 26 —
        // the registration returns noErr but events are never delivered. Dispatching
        // async ensures Carbon's event infrastructure is live before we register.
        let initialHotkey = model.config.hotkey
        DispatchQueue.main.async { [weak self] in
            self?.installHotkey(initialHotkey)
        }

        // First-launch hotkey seed: re-register via update() 500 ms after the
        // initial start() call. On macOS 26 the first-ever registration doesn't
        // deliver events; the update() path (unregister → re-register) does.
        // Guarded by a UserDefaults flag so it only runs once per install.
        if !UserDefaults.standard.bool(forKey: Self.hotkeySeededKey) {
            UserDefaults.standard.set(true, forKey: Self.hotkeySeededKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                self.installHotkey(self.model.config.hotkey)
            }
        }

        if UserDefaults.standard.bool(forKey: Self.setupCompletedKey) {
            settingsController?.show()
        } else {
            showOnboarding()
        }
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

    private func showOnboarding() {
        onboardingController = OnboardingWindowController(model: model) { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.setupCompletedKey)
            self?.onboardingController?.close()
            self?.onboardingController = nil
            self?.settingsController?.show()
        }
        onboardingController?.show()
    }

    private func observeSystemSettings() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemSettingsDeactivated(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )
    }

    @objc private func systemSettingsDeactivated(_ notification: Notification) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            app.bundleIdentifier == "com.apple.systempreferences"
        else { return }

        if let onboardingController {
            onboardingController.bringToFront()
        } else {
            settingsController?.show()
        }
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
