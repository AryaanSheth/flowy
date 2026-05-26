# 🌿 Flowey

Minimal local speech-to-text for **macOS**.
Hold a global hotkey → speak → release → text appears at the cursor.
Fully offline. No telemetry. Optional LLM cleanup via local Ollama.

> macOS-only for now — Windows & Linux are on the roadmap.

---

## Features

| Feature | Detail |
|---|---|
| **Local only** | Whisper runs on your Mac via whisper.cpp — no API keys, no network |
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

# CMake (for whisper.cpp)
brew install cmake

# Optional: Ollama for AI enhancement
brew install ollama
ollama pull llama3.2:3b
ollama serve   # runs in the background
```

---

## Download a Whisper model

Flowey uses GGML format models from [whisper.cpp](https://github.com/ggerganov/whisper.cpp/releases):

| Model | Size | Speed | Quality |
|---|---|---|---|
| `ggml-tiny.en.bin`  | 75 MB   | fastest | good |
| `ggml-base.en.bin`  | 141 MB  | fast    | **recommended** |
| `ggml-small.en.bin` | 461 MB  | medium  | better |
| `ggml-medium.en.bin`| 1.5 GB  | slow    | near human-level |

```bash
curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

Then set its path in **Settings → Model**.

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

Whisper is great at the audio→text part but tends to drop punctuation and
filler words. The optional Ollama pass cleans this up locally in ~200 ms on
Apple Silicon.

1. **Install Ollama**: `brew install ollama && ollama serve`
2. **Pull a small instruction-tuned model**:
   ```bash
   ollama pull llama3.2:3b      # ~2 GB, ~10 tok/s on M2
   # or
   ollama pull qwen2.5:3b       # similar, slightly different style
   ```
3. In Flowey, open **Settings → AI**, enable, click **Test**, pick the model.

Customise the system prompt to fit your style — for example, force lowercase
for terminal use, or have it strip filler words.

---

## Configuration file

| Path | |
|---|---|
| macOS | `~/Library/Application Support/flowey/config.json` |

Example `config.json`:

```json
{
  "modelPath": "/Users/you/models/ggml-base.en.bin",
  "hotkey": "CmdOrCtrl+Shift+Space",
  "autostart": false,
  "language": "en",
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

On first run the OS will prompt for two permissions:

1. **Microphone** — required for recording. Granted automatically on first record attempt.
2. **Accessibility** — required for keystroke injection.
   System Settings → Privacy & Security → Accessibility → enable `flowey`.

If you skip Accessibility, set **Output → Clipboard only** in Settings.
Flowey then copies transcribed text to your clipboard instead of typing it.

---

## Architecture

```
Global hotkey ─── key down ──► recording thread (cpal)
               └─ key up   ──► stop signal (AtomicBool)
                                    │
                             std::sync::mpsc
                                    │
                        pipeline thread (std::thread)
                          ├─ resample to 16 kHz mono (rubato)
                          ├─ transcribe              (whisper.cpp)
                          ├─ apply custom dictionary
                          ├─ optional Ollama cleanup (ureq HTTP)
                          ├─ store in history
                          └─ inject text             (enigo / arboard)
```

Frontend is plain HTML/CSS/JS (no framework, no build step) served via Tauri's
asset protocol. The Rust backend exposes Tauri commands consumed by the
settings window.

---

## License

MIT
