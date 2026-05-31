# Flowy

Minimal local speech-to-text for **macOS**.  
Hold a global hotkey → speak → release → text appears at the cursor.  
Fully offline. No telemetry. Optional LLM cleanup via local Ollama.

---

## Features

| Feature | Detail |
|---|---|
| **Local only** | Transcription uses macOS Speech Recognition — no API keys, no cloud |
| **Push-to-talk** | Hold a configurable global hotkey while speaking; text is injected on release |
| **Custom dictionary** | Word-substitution map applied after transcription |
| **Ollama enhancement** | Optional cleanup pass through a local LLM for punctuation & grammar |
| **Audio device picker** | Choose which microphone to record from |
| **Output modes** | Type into focused window, copy to clipboard, or both |
| **History** | Browse and copy your last 20 transcriptions |
| **Autostart** | Optional launch at login |

---

## Requirements

- macOS 13 Ventura or later (Apple Silicon)
- Xcode Command Line Tools

```bash
xcode-select --install
```

Optional — Ollama for AI enhancement:

```bash
brew install ollama
ollama pull llama3.2:3b
ollama serve
```

---

## Build

```bash
# Build and copy Flowy.app to /Applications
make build

# Build, then relaunch the running app
make relaunch

# Package a distributable DMG
make dmg
```

---

## Gatekeeper warning on first launch

When you open Flowy for the first time, macOS will block it with a message like
_"Flowy cannot be opened because it is from an unidentified developer"_ or flag it
as potentially malicious. This is expected — the app is not yet signed with an
Apple Developer ID certificate.

**Workaround (one-time):**

1. Right-click (or Control-click) `Flowy.app` → **Open**
2. Click **Open** in the dialog that appears

Or via System Settings:

1. Try to open Flowy normally — it will be blocked
2. Open **System Settings → Privacy & Security**
3. Scroll to the Security section and click **Open Anyway** next to the Flowy entry
4. Confirm with **Open**

You only need to do this once. After that, Flowy opens normally.

**Why this happens — and the proper fix:**

macOS Gatekeeper requires apps distributed outside the App Store to be signed
with a paid Apple Developer ID ($99/year) and notarized via Apple's notarization
service. Until Flowy is enrolled in the Apple Developer Program and the CI
pipeline is updated to sign and notarize the build, every downloaded copy will
trigger this warning.

Signing is on the roadmap. If you'd like to help or sponsor the developer
account, open an issue.

---

## macOS permissions

On first use the OS will prompt for:

1. **Speech Recognition** — required for transcription.
2. **Microphone** — required for recording.
3. **Accessibility** — required for keystroke injection.  
   System Settings → Privacy & Security → Accessibility → enable `Flowy`.

If Accessibility is not granted, Flowy falls back to copying text to the clipboard.

---

## Configuration

Config is written automatically on first launch.

| Path | |
|---|---|
| macOS | `~/Library/Application Support/flowy/config.json` |

```json
{
  "hotkey": "CmdOrCtrl+Shift+Space",
  "autostart": false,
  "dictionary": { "gonna": "going to", "wanna": "want to" },
  "inputDevice": null,
  "outputMode": "type",
  "maxRecordingSecs": 60,
  "historySize": 20,
  "ollamaEnabled": false,
  "ollamaEndpoint": "http://localhost:11434",
  "ollamaModel": "llama3.2:3b",
  "ollamaPrompt": "You are a transcription cleaner..."
}
```

---

## Architecture

Pure Swift / AppKit + SwiftUI macOS app. No Electron, no Tauri, no web layer.

```
Global hotkey ──► AppModel (SwiftUI @Observable)
                      │
               AVAudioEngine recording
                      │
               SFSpeechRecognizer (on-device)
                      │
               custom dictionary substitution
                      │
               optional Ollama HTTP pass
                      │
               CGEvent keystroke injection  ──► focused app
               (fallback: NSPasteboard)
```

---

## License

MIT
