# Flowy

Minimal local speech-to-text for **macOS**.  
Hold a global hotkey → speak → release → text appears at the cursor.  
Fully offline. No telemetry. No account. No subscription.

---

## Install

1. [Download the latest `.dmg`](https://github.com/AryaanSheth/flowy/releases/latest)
2. Drag **Flowy.app** into your Applications folder
3. **Right-click → Open** on first launch (Gatekeeper bypass for unsigned apps — one-time only)
4. Follow the setup wizard to grant Microphone, Speech Recognition, and Accessibility permissions

**Default hotkey:** `⌥ Space` (Alt+Space). Configurable in Settings.

**Requires:** macOS 13 Ventura or later, Apple Silicon

---

## Features

| Feature | Detail |
|---|---|
| **Local only** | Uses macOS on-device Speech Recognition — no API keys, no cloud |
| **Push-to-talk** | Hold a global hotkey while speaking; text injects on release |
| **Guided onboarding** | First-launch wizard walks through all required permissions |
| **Autosave settings** | Changes save automatically — no Save button |
| **Custom dictionary** | Word-substitution map applied after every transcription |
| **Auto-stop on silence** | VAD detects when you stop speaking and stops recording |
| **History** | Browse and copy your last 20 transcriptions |
| **Autostart** | Optional launch at login |

---

## Gatekeeper

Flowy is not yet signed with an Apple Developer certificate, so macOS blocks the first open.

**Fix (one-time):** Right-click `Flowy.app` → **Open** → **Open**

Alternatively: System Settings → Privacy & Security → scroll to Security → **Open Anyway**.

---

## Permissions

The setup wizard guides you through each permission on first launch:

1. **Speech Recognition** — required for transcription
2. **Microphone** — required for recording
3. **Accessibility** — required for keystroke injection into other apps (falls back to clipboard if not granted)

---

## Build from source

Requires Xcode Command Line Tools:

```bash
xcode-select --install
```

```bash
make build      # release build → target/release/bundle/macos/Flowy.app
make relaunch   # build + kill + relaunch
make dmg        # package distributable DMG
make check      # compile-only (no launch)
```

---

## Configuration

Settings save automatically. The config file lives at:

```
~/Library/Application Support/flowy/config.json
```

```json
{
  "hotkey": "Alt+Space",
  "autostart": false,
  "dictionary": {},
  "inputDevice": null,
  "maxRecordingSecs": 60,
  "vadEnabled": true,
  "vadSilenceSeconds": 0.6,
  "historySize": 20
}
```

---

## Architecture

Pure Swift · AppKit + SwiftUI · no Electron · no web layer

```
Global hotkey (Carbon RegisterEventHotKey)
       │
   AppModel (@MainActor)
       │
   AVAudioEngine + SFSpeechRecognizer (on-device)
       │
   dictionary substitution
       │
   CGEvent keystroke injection ──► focused app
   (fallback: NSPasteboard)
```

---

## License

MIT
