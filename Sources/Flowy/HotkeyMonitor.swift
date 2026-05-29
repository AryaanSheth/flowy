import Carbon
import Foundation

final class HotkeyMonitor {
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?

    private var parsedHotkey: ParsedHotkey
    private var hotkeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var registeredIDs = Set<UInt32>()
    private var keyHeld = false
    private var tapLatched = false
    private var pressStartedAt: Date?

    private static var nextID: UInt32 = 1
    private let tapLatchThreshold: TimeInterval = 0.35
    private let signature = OSType(
        (UInt32(Character("F").asciiValue!) << 24)
            | (UInt32(Character("l").asciiValue!) << 16)
            | (UInt32(Character("w").asciiValue!) << 8)
            | UInt32(Character("y").asciiValue!)
    )

    init(hotkey: String) throws {
        parsedHotkey = try ParsedHotkey.parse(hotkey)
    }

    func update(hotkey: String) throws {
        parsedHotkey = try ParsedHotkey.parse(hotkey)
        try registerCurrentHotkey()
    }

    func start() throws {
        stop()

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                return monitor.handle(event: event)
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        guard handlerStatus == noErr else {
            throw FlowyError.message("Could not install the global hotkey handler (\(handlerStatus)).")
        }

        try registerCurrentHotkey()
    }

    func stop() {
        for ref in hotkeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()
        registeredIDs.removeAll()

        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        handlerRef = nil

        keyHeld = false
        tapLatched = false
        pressStartedAt = nil
    }

    private func registerCurrentHotkey() throws {
        for ref in hotkeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()
        registeredIDs.removeAll()

        keyHeld = false
        tapLatched = false
        pressStartedAt = nil

        for modifiers in parsedHotkey.carbonModifierVariants {
            let id = Self.nextID
            Self.nextID += 1

            let hotkeyID = EventHotKeyID(signature: signature, id: id)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(parsedHotkey.keyCode),
                modifiers,
                hotkeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )

            guard status == noErr, let ref else {
                throw FlowyError.message("Could not register global hotkey '\(parsedHotkey.rawValue)'. It may already be used by macOS or another app.")
            }

            hotkeyRefs.append(ref)
            registeredIDs.insert(id)
        }
    }

    private func handle(event: EventRef) -> OSStatus {
        var hotkeyID = EventHotKeyID()
        let idStatus = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )

        guard idStatus == noErr, hotkeyID.signature == signature, registeredIDs.contains(hotkeyID.id) else {
            return noErr
        }

        let eventKind = GetEventKind(event)
        if eventKind == UInt32(kEventHotKeyPressed) {
            handlePressed()
        } else if eventKind == UInt32(kEventHotKeyReleased) {
            handleReleased()
        }

        return noErr
    }

    private func handlePressed() {
        guard !keyHeld else { return }
        keyHeld = true

        if tapLatched {
            tapLatched = false
            pressStartedAt = nil
            DispatchQueue.main.async { self.onStop?() }
            return
        }

        pressStartedAt = Date()
        DispatchQueue.main.async { self.onStart?() }
    }

    private func handleReleased() {
        guard keyHeld else { return }
        keyHeld = false

        let elapsed = pressStartedAt.map { Date().timeIntervalSince($0) } ?? tapLatchThreshold
        pressStartedAt = nil

        if elapsed < tapLatchThreshold {
            tapLatched = true
        } else {
            DispatchQueue.main.async { self.onStop?() }
        }
    }
}

private struct ParsedHotkey {
    var rawValue: String
    var commandOrControl = false
    var command = false
    var control = false
    var option = false
    var shift = false
    var keyCode: Int

    var carbonModifierVariants: [UInt32] {
        var base: UInt32 = 0
        if command { base |= UInt32(cmdKey) }
        if control { base |= UInt32(controlKey) }
        if option { base |= UInt32(optionKey) }
        if shift { base |= UInt32(shiftKey) }

        if commandOrControl {
            return [base | UInt32(cmdKey), base | UInt32(controlKey)]
        }

        return [base]
    }

    static func parse(_ raw: String) throws -> ParsedHotkey {
        let parts = raw
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let keyPart = parts.last else {
            throw FlowyError.message("Hotkey cannot be empty")
        }

        var hotkey = ParsedHotkey(rawValue: raw, keyCode: try keyCode(for: keyPart))
        for part in parts.dropLast() {
            switch part.lowercased() {
            case "cmdorctrl", "commandorcontrol":
                hotkey.commandOrControl = true
            case "cmd", "command", "meta":
                hotkey.command = true
            case "ctrl", "control":
                hotkey.control = true
            case "alt", "option", "opt":
                hotkey.option = true
            case "shift":
                hotkey.shift = true
            default:
                throw FlowyError.message("Unsupported hotkey modifier: \(part)")
            }
        }
        return hotkey
    }

    private static func keyCode(for key: String) throws -> Int {
        let normalized = key.lowercased()
        if let code = keyCodes[normalized] {
            return code
        }
        if normalized.count == 1, let scalar = normalized.unicodeScalars.first {
            let char = Character(scalar)
            if let code = keyCodes[String(char)] {
                return code
            }
        }
        throw FlowyError.message("Unsupported hotkey key: \(key)")
    }

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space,
        "return": kVK_Return,
        "enter": kVK_Return,
        "escape": kVK_Escape,
        "esc": kVK_Escape,
        "tab": kVK_Tab,
        "delete": kVK_Delete,
        "backspace": kVK_Delete,
        "left": kVK_LeftArrow,
        "right": kVK_RightArrow,
        "up": kVK_UpArrow,
        "down": kVK_DownArrow,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
        "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
        "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
        "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15, "f16": kVK_F16,
        "f17": kVK_F17, "f18": kVK_F18, "f19": kVK_F19, "f20": kVK_F20,
    ]
}
