use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

/// Persisted settings for the app.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Config {
    /// Path to the whisper ggml model file (.bin).
    pub model_path: String,

    /// Global hotkey string, e.g. "CmdOrCtrl+Shift+Space".
    pub hotkey: String,

    /// Whether to launch Flowey at system login.
    pub autostart: bool,

    /// Whisper language code, e.g. "en", or "auto" for auto-detect.
    pub language: String,

    /// Word-substitution map applied after transcription.
    /// Key = word to replace (case-insensitive), Value = replacement.
    pub dictionary: HashMap<String, String>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            model_path: String::new(),
            hotkey: "CmdOrCtrl+Shift+Space".into(),
            autostart: false,
            language: "auto".into(),
            dictionary: HashMap::new(),
        }
    }
}

impl Config {
    /// Load config from disk, falling back to defaults if absent or malformed.
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

    /// Persist the current config to disk.
    pub fn save(&self) -> anyhow::Result<()> {
        let path = Self::path()?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, serde_json::to_string_pretty(self)?)?;
        Ok(())
    }

    /// Returns the platform config file path: `<config_dir>/flowey/config.json`.
    pub fn path() -> anyhow::Result<PathBuf> {
        let base = dirs::config_dir()
            .ok_or_else(|| anyhow::anyhow!("Cannot determine config directory"))?;
        Ok(base.join("flowey").join("config.json"))
    }
}
