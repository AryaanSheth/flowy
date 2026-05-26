use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

// ── Output mode ──────────────────────────────────────────────

/// How transcribed text is delivered to the user.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum OutputMode {
    /// Simulate keystrokes into whatever window has focus (default).
    #[default]
    Type,
    /// Copy result to clipboard only (safe on all platforms).
    Clipboard,
    /// Both type AND copy to clipboard.
    TypeAndClipboard,
}

// ── Config ───────────────────────────────────────────────────

/// Persisted application settings.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Config {
    /// Path to the whisper ggml model file (.bin).
    pub model_path: String,

    /// Global PTT hotkey string, e.g. "CmdOrCtrl+Shift+Space".
    pub hotkey: String,

    /// Whether to launch Flowey at system login.
    pub autostart: bool,

    /// Whisper language code ("en", "fr", …) or "auto".
    pub language: String,

    /// Word-substitution map applied after transcription.
    pub dictionary: HashMap<String, String>,

    /// Preferred audio input device name.  `None` → system default.
    #[serde(default)]
    pub input_device: Option<String>,

    /// How transcribed text is delivered.
    #[serde(default)]
    pub output_mode: OutputMode,

    /// Safety cap: automatically stop recording after this many seconds.
    #[serde(default = "default_max_recording_secs")]
    pub max_recording_secs: u32,

    /// How many past transcriptions to keep in memory.
    #[serde(default = "default_history_size")]
    pub history_size: usize,
}

fn default_max_recording_secs() -> u32 { 60 }
fn default_history_size()       -> usize { 20 }

impl Default for Config {
    fn default() -> Self {
        Self {
            model_path:          String::new(),
            hotkey:              "CmdOrCtrl+Shift+Space".into(),
            autostart:           false,
            language:            "auto".into(),
            dictionary:          HashMap::new(),
            input_device:        None,
            output_mode:         OutputMode::Type,
            max_recording_secs:  default_max_recording_secs(),
            history_size:        default_history_size(),
        }
    }
}

impl Config {
    /// Load from disk, falling back to defaults if absent or malformed.
    pub fn load() -> Self {
        match Self::try_load() {
            Ok(c) => c,
            Err(e) => {
                log::warn!("Could not load config, using defaults: {e}");
                Self::default()
            }
        }
    }

    fn try_load() -> anyhow::Result<Self> {
        let path = Self::path()?;
        if !path.exists() {
            return Ok(Self::default());
        }
        let raw = std::fs::read_to_string(&path)?;
        Ok(serde_json::from_str(&raw)?)
    }

    /// Persist to disk.
    pub fn save(&self) -> anyhow::Result<()> {
        let path = Self::path()?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, serde_json::to_string_pretty(self)?)?;
        Ok(())
    }

    /// `<config_dir>/flowey/config.json`
    pub fn path() -> anyhow::Result<PathBuf> {
        let base = dirs::config_dir()
            .ok_or_else(|| anyhow::anyhow!("Cannot determine config directory"))?;
        Ok(base.join("flowey").join("config.json"))
    }
}
