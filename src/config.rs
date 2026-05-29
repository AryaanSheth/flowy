use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

// ── Output mode ───────────────────────────────────────────────

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

// ── Config ────────────────────────────────────────────────────

/// Persisted application settings.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Config {
    /// Global PTT hotkey string, e.g. "CmdOrCtrl+Shift+Space".
    pub hotkey: String,

    /// Whether to launch Flowey at system login.
    pub autostart: bool,

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

    // ── Ollama post-processor ────────────────────────────────

    /// Whether to clean up transcribed text through a local Ollama model.
    #[serde(default)]
    pub ollama_enabled: bool,

    /// Ollama HTTP endpoint, default `http://localhost:11434`.
    #[serde(default = "default_ollama_endpoint")]
    pub ollama_endpoint: String,

    /// Model tag to use, e.g. `llama3.2:3b`.
    #[serde(default = "default_ollama_model")]
    pub ollama_model: String,

    /// System prompt that tells the model what to do with the dictated text.
    #[serde(default = "default_ollama_prompt")]
    pub ollama_prompt: String,
}

fn default_max_recording_secs() -> u32   { 60 }
fn default_history_size()       -> usize { 20 }
fn default_ollama_endpoint()    -> String { "http://localhost:11434".into() }
fn default_ollama_model()       -> String { "llama3.2:3b".into() }
fn default_ollama_prompt()      -> String {
    "You are a transcription cleaner. Fix punctuation, capitalization and \
     grammar in the dictated text. Preserve the speaker's exact words and \
     meaning — do not add new content, summaries, or commentary. Return only \
     the cleaned text.".into()
}

impl Default for Config {
    fn default() -> Self {
        Self {
            hotkey:             "CmdOrCtrl+Shift+Space".into(),
            autostart:          false,
            dictionary:         HashMap::new(),
            input_device:       None,
            output_mode:        OutputMode::Type,
            max_recording_secs: default_max_recording_secs(),
            history_size:       default_history_size(),
            ollama_enabled:     false,
            ollama_endpoint:    default_ollama_endpoint(),
            ollama_model:       default_ollama_model(),
            ollama_prompt:      default_ollama_prompt(),
        }
    }
}

impl Config {
    /// Load from disk, falling back to defaults if absent or malformed.
    pub fn load() -> Self {
        match Self::try_load() {
            Ok(c)  => c.sanitized(),
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
        // Unknown fields (e.g. modelPath from an old config) are silently ignored.
        Ok(serde_json::from_str(&raw)?)
    }

    /// Persist to disk.
    pub fn save(&self) -> anyhow::Result<()> {
        let path = Self::path()?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, serde_json::to_string_pretty(&self.clone().sanitized())?)?;
        Ok(())
    }

    /// `~/Library/Application Support/flowey/config.json`
    pub fn path() -> anyhow::Result<PathBuf> {
        let home = std::env::var("HOME")
            .map(PathBuf::from)
            .map_err(|_| anyhow::anyhow!("$HOME is not set"))?;
        Ok(home
            .join("Library")
            .join("Application Support")
            .join("flowey")
            .join("config.json"))
    }

    pub(crate) fn sanitized(mut self) -> Self {
        if self.hotkey.trim().is_empty() {
            self.hotkey = Self::default().hotkey;
        } else {
            self.hotkey = self.hotkey.trim().to_string();
        }

        self.input_device = self
            .input_device
            .and_then(|d| {
                let d = d.trim().to_string();
                if d.is_empty() { None } else { Some(d) }
            });

        self.max_recording_secs = self.max_recording_secs.clamp(5, 300);
        self.history_size = self.history_size.clamp(1, 200);

        if self.ollama_endpoint.trim().is_empty() {
            self.ollama_endpoint = default_ollama_endpoint();
        } else {
            self.ollama_endpoint = self.ollama_endpoint.trim().to_string();
        }

        if self.ollama_model.trim().is_empty() {
            self.ollama_model = default_ollama_model();
        } else {
            self.ollama_model = self.ollama_model.trim().to_string();
        }

        if self.ollama_prompt.trim().is_empty() {
            self.ollama_prompt = default_ollama_prompt();
        } else {
            self.ollama_prompt = self.ollama_prompt.trim().to_string();
        }

        self
    }
}
