use std::sync::{
    atomic::AtomicBool,
    mpsc::SyncSender,
    Arc,
};

use parking_lot::{Mutex, RwLock};
use tauri::AppHandle;

use crate::config::Config;
use crate::transcribe::Transcriber;

/// Three-state indicator shown on the tray icon.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub enum AppStatus {
    Idle,
    Recording,
    Transcribing,
}

/// Raw audio buffer, sample-rate and channel count coming from the recording thread.
pub type AudioData = (Vec<f32>, u32, u16);

/// Central application state shared across Tauri commands, the hotkey handler,
/// and the background pipeline thread via `Arc`.
pub struct AppState {
    /// Set to `true` while the PTT key is held, `false` on release.
    /// The recording thread polls this flag.
    pub stop_signal: Mutex<Option<Arc<AtomicBool>>>,

    /// Persisted user settings (hot-reloaded on save).
    pub config: RwLock<Config>,

    /// Loaded Whisper model.  `None` until the model path is configured.
    pub transcriber: Mutex<Option<Transcriber>>,

    /// Current pipeline status (drives tray icon).
    pub status: Mutex<AppStatus>,

    /// Channel end for sending captured audio to the pipeline thread.
    pub audio_tx: SyncSender<AudioData>,

    /// Tauri app handle, populated in the `setup` hook so the pipeline thread
    /// can update the tray icon.
    pub app_handle: Mutex<Option<AppHandle>>,
}

impl AppState {
    pub fn new(config: Config, audio_tx: SyncSender<AudioData>) -> Self {
        Self {
            stop_signal: Mutex::new(None),
            config: RwLock::new(config),
            transcriber: Mutex::new(None),
            status: Mutex::new(AppStatus::Idle),
            audio_tx,
            app_handle: Mutex::new(None),
        }
    }
}
