use std::{
    collections::VecDeque,
    sync::{atomic::AtomicBool, mpsc::SyncSender, Arc},
};

use parking_lot::{Mutex, RwLock};
use tauri::AppHandle;

use crate::config::Config;

/// Pipeline status — drives the tray icon and settings-window status badge.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub enum AppStatus {
    Idle,
    Recording,
    Transcribing,
}

/// Raw audio buffer, sample-rate and channel count from the recording thread.
pub type AudioData = (Vec<f32>, u32, u16);

/// Central application state shared across Tauri commands, the hotkey handler,
/// and the background pipeline thread via `Arc`.
pub struct AppState {
    /// Set to `true` once the PTT key is released; recording thread checks this.
    pub stop_signal: Mutex<Option<Arc<AtomicBool>>>,

    /// Persisted user settings (hot-reloaded on save from Settings window).
    pub config: RwLock<Config>,

    /// Current pipeline status.
    pub status: Mutex<AppStatus>,

    /// Channel for sending captured audio → the pipeline thread.
    pub audio_tx: SyncSender<AudioData>,

    /// Tauri app handle, set in the `setup` hook so the pipeline thread
    /// can update the tray icon without a static reference.
    pub app_handle: Mutex<Option<AppHandle>>,

    /// Last N transcription results (newest first).
    pub history: Mutex<VecDeque<String>>,
}

impl AppState {
    pub fn new(config: Config, audio_tx: SyncSender<AudioData>) -> Self {
        Self {
            stop_signal: Mutex::new(None),
            config:      RwLock::new(config),
            status:      Mutex::new(AppStatus::Idle),
            audio_tx,
            app_handle:  Mutex::new(None),
            history:     Mutex::new(VecDeque::new()),
        }
    }
}
