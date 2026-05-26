use std::{collections::HashMap, sync::Arc};

use tauri::{command, AppHandle, State};
use tauri_plugin_autostart::ManagerExt;
use tauri_plugin_dialog::DialogExt;
use tauri_plugin_global_shortcut::GlobalShortcutExt;

use crate::{
    config::Config,
    state::{AppState, AppStatus},
    transcribe::Transcriber,
};

// ── Config ────────────────────────────────────────────────────

/// Return the current configuration for the settings window.
#[command]
pub fn get_config(state: State<Arc<AppState>>) -> Config {
    state.config.read().clone()
}

/// Persist an updated configuration, applying side effects:
///   - Hotkey changes   → un-register old, register new
///   - Autostart toggle → enable/disable OS autostart
///   - Model path change → reload Whisper in background
#[command]
pub async fn save_config(
    new_config: Config,
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<(), String> {
    let old_config = state.config.read().clone();

    // Persist first so a reload race sees the new value.
    new_config.save().map_err(|e| e.to_string())?;

    // ── Hotkey ──────────────────────────────────────────────
    if new_config.hotkey != old_config.hotkey {
        let gs = app.global_shortcut();
        // Targeted un-register — do NOT use unregister_all() as it would
        // destroy shortcuts registered by other plugins.
        if let Err(e) = gs.unregister(old_config.hotkey.as_str()) {
            log::warn!("Could not unregister old hotkey '{}': {e}", old_config.hotkey);
        }
        crate::hotkey::register_shortcut(&app, &state, &new_config.hotkey);
    }

    // ── Autostart ────────────────────────────────────────────
    if new_config.autostart != old_config.autostart {
        let al = app.autolaunch();
        let result = if new_config.autostart { al.enable() } else { al.disable() };
        if let Err(e) = result {
            log::warn!("Autostart toggle failed: {e}");
        }
    }

    // ── Whisper model ────────────────────────────────────────
    if new_config.model_path != old_config.model_path && !new_config.model_path.is_empty() {
        let path = new_config.model_path.clone();
        let state_arc = Arc::clone(&*state);
        tauri::async_runtime::spawn_blocking(move || {
            match Transcriber::load(&path) {
                Ok(t) => {
                    *state_arc.transcriber.lock() = Some(t);
                    log::info!("Model loaded from '{path}'");
                }
                Err(e) => log::error!("Failed to load model: {e}"),
            }
        });
    }

    // Commit to shared state.
    *state.config.write() = new_config;
    Ok(())
}

// ── Status & history ─────────────────────────────────────────

/// Return the current pipeline status.
#[command]
pub fn get_status(state: State<Arc<AppState>>) -> AppStatus {
    *state.status.lock()
}

/// Return recent transcriptions, newest first.
#[command]
pub fn get_history(state: State<Arc<AppState>>) -> Vec<String> {
    state.history.lock().iter().cloned().collect()
}

/// Wipe the transcription history.
#[command]
pub fn clear_history(state: State<Arc<AppState>>) {
    state.history.lock().clear();
}

// ── Audio devices ─────────────────────────────────────────────

/// List available audio input devices.
/// First entry is always "" meaning "System default".
#[command]
pub fn list_audio_devices() -> Vec<String> {
    crate::audio::list_input_devices()
}

// ── File picker ───────────────────────────────────────────────

/// Open a native file-picker and return the selected path (for model browsing).
#[command]
pub async fn browse_model_file(app: AppHandle) -> Option<String> {
    app.dialog()
        .file()
        .add_filter("Whisper GGML Model", &["bin"])
        .blocking_pick_file()
        .map(|p| p.to_string())
}

// ── Dictionary preview ────────────────────────────────────────

/// Live-preview a dictionary substitution without saving.
#[command]
pub fn test_dictionary(input: String, dict: HashMap<String, String>) -> String {
    crate::dictionary::apply(&input, &dict)
}
