use std::sync::{atomic::{AtomicBool, Ordering}, Arc};

use tauri::AppHandle;
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};

use crate::state::{AppState, AppStatus};

/// Register the push-to-talk shortcut.
///
/// - **Key down** → start a recording thread, update tray to Recording.
/// - **Key up**   → signal the recording thread to stop; the pipeline thread
///                  receives the audio and handles resampling + transcription.
pub fn register_shortcut(app: &AppHandle, state: &Arc<AppState>, hotkey: &str) {
    let state = Arc::clone(state);
    let app_clone = app.clone();

    let result = app.global_shortcut().on_shortcut(hotkey, move |_app, _shortcut, event| {
        match event.state {
            ShortcutState::Pressed  => on_press(&app_clone, &state),
            ShortcutState::Released => on_release(&state),
        }
    });

    if let Err(e) = result {
        log::error!("Failed to register hotkey '{hotkey}': {e}");
    } else {
        log::info!("Hotkey registered: {hotkey}");
    }
}

fn on_press(app: &AppHandle, state: &Arc<AppState>) {
    // Guard against double-press (key repeat).
    if state.stop_signal.lock().is_some() {
        return;
    }

    let stop = Arc::new(AtomicBool::new(false));
    *state.stop_signal.lock() = Some(Arc::clone(&stop));

    // Update status.
    *state.status.lock() = AppStatus::Recording;
    update_tray(app, state);

    let tx = state.audio_tx.clone();
    std::thread::spawn(move || {
        match crate::audio::record_until_stopped(stop) {
            Ok(data) => {
                if let Err(e) = tx.send(data) {
                    log::error!("Audio pipeline channel closed: {e}");
                }
            }
            Err(e) => log::error!("Recording error: {e}"),
        }
    });
}

fn on_release(state: &Arc<AppState>) {
    if let Some(sig) = state.stop_signal.lock().take() {
        sig.store(true, Ordering::Relaxed);
    }
    // Status will flip to Transcribing once the pipeline thread picks up the audio.
}

// ---------------------------------------------------------------------------
// Tray status update (best-effort — the tray handle is optional at this point)
// ---------------------------------------------------------------------------

fn update_tray(app: &AppHandle, state: &Arc<AppState>) {
    let status = *state.status.lock();
    if let Some(tray) = app.tray_by_id("main") {
        crate::tray::update_status(&tray, status);
    }
}
