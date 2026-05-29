# 🌿 Flowy

Minimal local speech-to-text for **macOS**.
Hold a global hotkey → speak → release → text appears at the cursor.
Fully offline. No telemetry. Optional LLM cleanup via local Ollama.

> macOS-only for now — Windows & Linux are on the roadmap.

---

## Features

| Feature | Detail |
|---|---|
| **Local only** | Transcription uses macOS Speech Recognition on your Mac — no API keys, no app server |
| **Push-to-talk** | Hold a configurable global hotkey while speaking; text is injected on release |
| **Custom dictionary** | Word-substitution map applied after transcription |
| **Ollama enhancement** | Optional cleanup pass through a local LLM (e.g. `llama3.2:3b`) for punctuation & grammar |
| **Audio device picker** | Choose which microphone to record from |
| **Output modes** | Type into focused window, copy to clipboard, or both |
| **History** | Browse and copy your last 20 transcriptions |
| **Autostart** | Optional launch at login |
| **Minimal footprint** | Tauri (not Electron) — native webview, ~15 MB binary |

---

## Prerequisites

```bash
# Xcode Command Line Tools (Clang + headers)
xcode-select --install

# Rust toolchain (≥ 1.77)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Tauri CLI
cargo install tauri-cli --version "^2"

# Optional: Ollama for AI enhancement
brew install ollama
ollama pull llama3.2:3b
ollama serve   # runs in the background
```

---

## Run

### Development

```bash
cargo tauri dev
```

The settings window is hidden at startup. Right-click the tray icon → **Settings**.

### Build a .dmg

```bash
# Regenerate icons from a 1024×1024 source PNG (optional)
cargo tauri icon icons/icon.png

# Build
cargo tauri build
```

The signed `.dmg` is placed in `target/release/bundle/dmg/`.

---

## Ollama post-processing (optional)

macOS Speech Recognition handles the audio→text part locally. The optional
Ollama pass can clean up punctuation and capitalization locally in ~200 ms on
Apple Silicon.

1. **Install Ollama**: `brew install ollama && ollama serve`
2. **Pull a small instruction-tuned model**:
   ```bash
   ollama pull llama3.2:3b      # ~2 GB, ~10 tok/s on M2
   # or
   ollama pull qwen2.5:3b       # similar, slightly different style
   ```
3. In Flowy, open **Settings → AI**, enable, click **Test**, pick the model.

Customise the system prompt to fit your style — for example, force lowercase
for terminal use, or have it strip filler words.

---

## Configuration file

| Path | |
|---|---|
| macOS | `~/Library/Application Support/flowy/config.json` |

Example `config.json`:

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

## macOS permissions

On first use the OS may prompt for three permissions:

1. **Speech Recognition** — required for transcription.
2. **Microphone** — required for recording. Granted automatically on first record attempt.
3. **Accessibility** — required for keystroke injection.
   System Settings → Privacy & Security → Accessibility → enable `flowy`.

If Accessibility is unavailable, Flowy falls back to copying transcribed text
to your clipboard so you can paste manually.

---

## Architecture

```
Global hotkey ─── key down ──► recording thread (cpal)
               └─ key up   ──► stop signal (AtomicBool)
                                    │
                             std::sync::mpsc
                                    │
                        pipeline thread (std::thread)
                          ├─ downmix + write temp WAV
                          ├─ transcribe              (macOS SFSpeechRecognizer)
                          ├─ apply custom dictionary
                          ├─ optional Ollama cleanup (ureq HTTP)
                          ├─ store in history
                          └─ inject text             (NSPasteboard + CGEvent)
```

Frontend is plain HTML/CSS/JS (no framework, no build step) served via Tauri's
asset protocol. The Rust backend exposes Tauri commands consumed by the
settings window.

---

## License

MIT
