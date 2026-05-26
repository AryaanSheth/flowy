use std::{collections::HashMap, sync::Arc};

use tauri::{command, AppHandle, State};
use tauri_plugin_autostart::ManagerExt;
use tauri_plugin_dialog::DialogExt;

use crate::{
    config::Config,
    state::{AppState, AppStatus},
    transcribe::Transcriber,
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn re_register_shortcut(app: &AppHandle, state: &Arc<AppState>, hotkey: &str) {
    use tauri_plugin_global_shortcut::GlobalShortcutExt;
    let gs = app.global_shortcut();
    let _ = gs.unregister_all();
    crate::hotkey::register_shortcut(app, state, hotkey);
}

// ---------------------------------------------------------------------------
// Commands called from the Settings window
// ---------------------------------------------------------------------------

/// Return the current configuration (serialised as JSON for the frontend).
#[command]
pub fn get_config(state: State<Arc<AppState>>) -> Config {
    state.config.read().clone()
}

/// Persist an updated configuration.
///
/// Side effects:
///   - Re-registers the global hotkey if it changed.
///   - Toggles autostart.
///   - Reloads the Whisper model if the model path changed.
#[command]
pub async fn save_config(
    new_config: Config,
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<(), String> {
    let old_config = state.config.read().clone();

    // Persist to disk first.
    new_config.save().map_err(|e| e.to_string())?;

    // Hotkey changed → re-register.
    if new_config.hotkey != old_config.hotkey {
        re_register_shortcut(&app, &state, &new_config.hotkey);
    }

    // Autostart changed.
    if new_config.autostart != old_config.autostart {
        let al = app.autolaunch();
        let result = if new_config.autostart {
            al.enable()
        } else {
            al.disable()
        };
        if let Err(e) = result {
            log::warn!("Autostart toggle failed: {e}");
        }
    }

    // Model path changed → reload Whisper.
    if new_config.model_path != old_config.model_path {
        let path = new_config.model_path.clone();
        // Clone the outer Arc<AppState> so the blocking task owns it.
        let state_arc = Arc::clone(&*state);
        // Run on a blocking thread since model loading can take a moment.
        tauri::async_runtime::spawn_blocking(move || {
            match Transcriber::load(&path) {
                Ok(t) => {
                    *state_arc.transcriber.lock() = Some(t);
                    log::info!("Model reloaded from '{path}'");
                }
                Err(e) => log::error!("Failed to reload model: {e}"),
            }
        });
    }

    // Commit the new config into shared state.
    *state.config.write() = new_config;

    Ok(())
}

/// Return the current pipeline status (for the settings UI indicator).
#[command]
pub fn get_status(state: State<Arc<AppState>>) -> AppStatus {
    *state.status.lock()
}

/// Open a native file-picker and return the chosen path (for model selection).
#[command]
pub async fn browse_model_file(app: AppHandle) -> Option<String> {
    app.dialog()
        .file()
        .add_filter("Whisper GGML Model", &["bin"])
        .blocking_pick_file()
        .map(|p| p.to_string())
}

/// Live-preview a dictionary substitution without saving.
#[command]
pub fn test_dictionary(input: String, dict: HashMap<String, String>) -> String {
    crate::dictionary::apply(&input, &dict)
}
