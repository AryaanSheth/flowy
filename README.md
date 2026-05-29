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
