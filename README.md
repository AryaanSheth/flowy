# 🌿 Flowey

Minimal local speech-to-text for the desktop.  
Hold a global hotkey → speak → release → text appears at the cursor.  
Fully offline. No telemetry. Tiny binary.

---

## Features

| Feature | Detail |
|---|---|
| **Local only** | Whisper runs on your CPU/GPU via whisper.cpp — no API keys, no network |
| **Push-to-talk** | Hold a configurable global hotkey while speaking; text is injected on release |
| **Custom dictionary** | Word-substitution map applied after transcription (e.g. "gonna → going to") |
| **Autostart** | Optional launch at login via the OS autostart mechanism |
| **Minimal footprint** | Tauri (not Electron) — native webview, ~10 MB binary |

---

## Prerequisites

### All platforms
- **Rust ≥ 1.77** — [rustup.rs](https://rustup.rs)
- **Tauri CLI** — `cargo install tauri-cli --version "^2"`
- **CMake** — required to compile whisper.cpp (bundled in `whisper-rs`)
- **A C++ compiler** — `clang++` / `g++` / MSVC

### Linux
```bash
# Ubuntu / Debian
sudo apt install \
  libwebkit2gtk-4.1-dev libssl-dev libgtk-3-dev libayatana-appindicator3-dev \
  librsvg2-dev cmake build-essential
```

### macOS
- Xcode Command Line Tools: `xcode-select --install`

### Windows
- Visual Studio Build Tools (C++ workload) + CMake

---

## Download a Whisper model

Flowey uses the [GGML format](https://github.com/ggerganov/whisper.cpp/releases) from whisper.cpp:

| Model | Size | Speed | Quality |
|---|---|---|---|
| `ggml-tiny.en.bin`  | 75 MB   | fastest | good for English |
| `ggml-base.en.bin`  | 141 MB  | fast    | **recommended** |
| `ggml-small.en.bin` | 461 MB  | medium  | better accuracy |
| `ggml-medium.en.bin`| 1.5 GB  | slow    | near human-level |

```bash
# Example — base English model
curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

Then set the path in **Settings** (tray icon → Settings).

---

## Running in development

```bash
cargo tauri dev
```

The settings window is hidden at startup; right-click the tray icon → **Settings**.

---

## Building a release binary

```bash
# Regenerate icons from a proper source image first (optional but recommended):
cargo tauri icon icons/icon.png

# Build
cargo tauri build
```

The installer / AppImage / .dmg / .exe is placed in `target/release/bundle/`.

---

## Configuration

Settings are stored at:

| Platform | Path |
|---|---|
| Linux   | `~/.config/flowey/config.json` |
| macOS   | `~/Library/Application Support/flowey/config.json` |
| Windows | `%APPDATA%\flowey\config.json` |

Example `config.json`:

```json
{
  "modelPath": "/home/alice/models/ggml-base.en.bin",
  "hotkey": "CmdOrCtrl+Shift+Space",
  "autostart": false,
  "language": "en",
  "dictionary": {
    "gonna": "going to",
    "wanna": "want to",
    "kinda": "kind of"
  }
}
```

---

## Platform notes

### Linux (Wayland)
Global shortcuts require either **XWayland** or a compositor with the
`zwp_keyboard_shortcuts_inhibit_manager_v1` protocol.  
Text injection via `enigo` works on X11; on pure Wayland you may need
`ydotool` (requires the user in the `input` group or `uinput` access):

```bash
sudo usermod -aG input $USER   # then log out and back in
```

### macOS
The first time text is injected, macOS will prompt for
**Accessibility** permission (System Settings → Privacy & Security → Accessibility).
Without it, transcription runs but text will not be typed.  
Microphone permission is requested automatically by the OS on first recording.

### Windows
The keystroke injector (`enigo`/`SendInput`) is blocked for UAC-elevated windows.
This is a known OS limitation. Code-signing the binary reduces antivirus false positives.

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
                          ├─ transcribe (whisper-rs / whisper.cpp)
                          ├─ apply custom dictionary
                          └─ inject text (enigo)
```

Frontend is plain HTML/CSS/JS (no framework, no build step) served via Tauri's
asset protocol.  The Rust backend exposes four Tauri commands:
`get_config`, `save_config`, `get_status`, `test_dictionary`.

---

## License

MIT
