use std::{
    collections::HashMap,
    sync::{atomic::{AtomicBool, Ordering}, Arc},
};

use tauri::{command, AppHandle, Emitter, State};
use tauri_plugin_autostart::ManagerExt;
use tauri_plugin_global_shortcut::GlobalShortcutExt;

use crate::{
    config::Config,
    state::{AppState, AppStatus},
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
#[command]
pub async fn save_config(
    new_config: Config,
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<(), String> {
    let old_config = state.config.read().clone();

    new_config.save().map_err(|e| e.to_string())?;

    // ── Hotkey ───────────────────────────────────────────────
    if new_config.hotkey != old_config.hotkey {
        let gs = app.global_shortcut();
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

    *state.config.write() = new_config;
    Ok(())
}

// ── Status & history ──────────────────────────────────────────

#[command]
pub fn get_status(state: State<Arc<AppState>>) -> AppStatus {
    *state.status.lock()
}

#[command]
pub fn get_history(state: State<Arc<AppState>>) -> Vec<String> {
    state.history.lock().iter().cloned().collect()
}

#[command]
pub fn clear_history(state: State<Arc<AppState>>) {
    state.history.lock().clear();
}

// ── Recording (UI button) ─────────────────────────────────────

/// Start recording from the settings UI (bypasses the global hotkey).
#[command]
pub fn start_recording(app: AppHandle, state: State<Arc<AppState>>) {
    let mut sig_guard = state.stop_signal.lock();
    if sig_guard.is_some() { return; } // already recording

    let stop = Arc::new(AtomicBool::new(false));
    *sig_guard = Some(Arc::clone(&stop));
    drop(sig_guard);

    let (device_name, max_secs) = {
        let cfg = state.config.read();
        (cfg.input_device.clone(), cfg.max_recording_secs)
    };

    *state.status.lock() = AppStatus::Recording;
    let _ = app.emit("flowey:status", AppStatus::Recording);
    if let Some(tray) = app.tray_by_id("main") {
        crate::tray::update_status(&tray, AppStatus::Recording);
    }

    let tx = state.audio_tx.clone();
    std::thread::Builder::new()
        .name("flowey-record-ui".into())
        .spawn(move || {
            match crate::audio::record_until_stopped(stop, device_name.as_deref(), max_secs) {
                Ok(data) => { let _ = tx.try_send(data); }
                Err(e)   => log::error!("Recording error: {e}"),
            }
        })
        .expect("spawn record thread");
}

/// Stop an in-progress recording (triggered by releasing the UI button).
#[command]
pub fn stop_recording(state: State<Arc<AppState>>) {
    if let Some(sig) = state.stop_signal.lock().take() {
        sig.store(true, Ordering::Relaxed);
    }
}

// ── Permissions ───────────────────────────────────────────────

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Permissions {
    pub speech:        bool,
    pub accessibility: bool,
}

#[command]
pub fn check_permissions() -> Permissions {
    Permissions {
        speech:        crate::transcribe::is_authorized(),
        accessibility: crate::transcribe::is_accessibility_trusted(),
    }
}

// ── Audio devices ─────────────────────────────────────────────

#[command]
pub fn list_audio_devices() -> Vec<String> {
    crate::audio::list_input_devices()
}

// ── Ollama ────────────────────────────────────────────────────

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OllamaStatus {
    pub reachable: bool,
    pub models:    Vec<String>,
    pub error:     Option<String>,
}

#[command]
pub fn check_ollama(endpoint: String) -> OllamaStatus {
    if !crate::ollama::ping(&endpoint) {
        return OllamaStatus {
            reachable: false,
            models:    vec![],
            error:     Some(format!("Cannot reach Ollama at {endpoint}. Is it running?")),
        };
    }
    match crate::ollama::list_models(&endpoint) {
        Ok(models) => OllamaStatus { reachable: true, models, error: None },
        Err(e)     => OllamaStatus {
            reachable: true,
            models:    vec![],
            error:     Some(e.to_string()),
        },
    }
}

// ── Dictionary preview ────────────────────────────────────────

#[command]
pub fn test_dictionary(input: String, dict: HashMap<String, String>) -> String {
    crate::dictionary::apply(&input, &dict)
}
