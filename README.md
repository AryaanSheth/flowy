# Flowy

Minimal local speech-to-text for **macOS**.  
Hold a global hotkey → speak → words appear at the cursor as you talk.  
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
| **Live push-to-talk** | Hold a global hotkey while speaking; text streams into the focused window from partial recognition results |
| **Voice punctuation** | Say "period", "comma", "new line", "new paragraph", and related commands to insert punctuation and line breaks |
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

### Auto-update release setup

Flowy can bundle Sparkle for app updates. Local builds work without Sparkle;
release builds enable it when the Sparkle key material is configured.

1. Run `make sparkle-install` to download `Sparkle.framework` into `vendor/Sparkle`.
2. Generate a Sparkle EdDSA key with `vendor/Sparkle/bin/generate_keys`.
3. Add the public key to the GitHub repository variable `FLOWY_SPARKLE_PUBLIC_ED_KEY`.
4. Export the private key and add it to the GitHub secret `FLOWY_SPARKLE_PRIVATE_ED_KEY`.

Tagged releases upload `appcast.xml` when the private key is present. The app
uses `https://github.com/AryaanSheth/flowy/releases/latest/download/appcast.xml`
as its update feed. Sparkle release notes are embedded directly in `appcast.xml`
so the updater shows a small Flowy-branded changelog instead of embedding GitHub.

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
  "feedbackSoundsEnabled": true,
  "activeMenuBarLabelEnabled": true,
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
   AVAudioEngine + SFSpeechRecognizer partials (on-device)
       │
   dictionary substitution + spoken punctuation
       │
   StreamingInjector partial reconciliation ──► focused app
   (fallback: NSPasteboard)
       │
   final pass: amendments / optional local rewrite / translation
       │
   final reconciliation or clipboard fallback
```

---

## License

MIT
