use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

use tauri::AppHandle;
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};

use crate::state::{AppState, AppStatus};

/// Register (or re-register) the push-to-talk shortcut.
///
/// Call `app.global_shortcut().unregister(old_hotkey)` before calling this
/// when the hotkey changes — do **not** use `unregister_all()` as that would
/// destroy shortcuts registered by other plugins or components.
pub fn register_shortcut(app: &AppHandle, state: &Arc<AppState>, hotkey: &str) {
    let state = Arc::clone(state);
    let app_clone = app.clone();

    let result = app.global_shortcut().on_shortcut(hotkey, move |_app, _shortcut, event| {
        match event.state {
            ShortcutState::Pressed  => on_press(&app_clone, &state),
            ShortcutState::Released => on_release(&state),
        }
    });

    match result {
        Ok(()) => log::info!("Hotkey registered: {hotkey}"),
        Err(e) => log::error!("Failed to register hotkey '{hotkey}': {e} — check it is not already taken by another app"),
    }
}

// ── Key-press handler ─────────────────────────────────────────

fn on_press(app: &AppHandle, state: &Arc<AppState>) {
    // Guard against OS key-repeat: only start a new recording if none is
    // currently in progress.  We hold the lock for the full check-and-set to
    // eliminate the TOCTOU window.
    let mut sig_guard = state.stop_signal.lock();
    if sig_guard.is_some() {
        return; // already recording
    }

    // Create a fresh stop-signal for this session.
    let stop = Arc::new(AtomicBool::new(false));
    *sig_guard = Some(Arc::clone(&stop));
    drop(sig_guard); // release before spawning thread

    // Snapshot config values needed by the recording thread.
    let (device_name, max_secs) = {
        let cfg = state.config.read();
        (cfg.input_device.clone(), cfg.max_recording_secs)
    };

    // Update status.
    *state.status.lock() = AppStatus::Recording;
    update_tray(app, state);

    let tx = state.audio_tx.clone();
    std::thread::Builder::new()
        .name("flowey-record".into())
        .spawn(move || {
            match crate::audio::record_until_stopped(stop, device_name.as_deref(), max_secs) {
                Ok(data) => {
                    // Non-blocking try-send: if the pipeline is still busy,
                    // drop the audio rather than blocking the thread.
                    if let Err(e) = tx.try_send(data) {
                        log::warn!("Pipeline busy, audio dropped: {e}");
                    }
                }
                Err(e) => log::error!("Recording error: {e}"),
            }
        })
        .expect("Failed to spawn recording thread");
}

// ── Key-release handler ───────────────────────────────────────

fn on_release(state: &Arc<AppState>) {
    if let Some(sig) = state.stop_signal.lock().take() {
        sig.store(true, Ordering::Relaxed);
    }
    // Status will flip to Transcribing once the pipeline picks up the audio,
    // and back to Idle once transcription finishes.
}

// ── Tray update ───────────────────────────────────────────────

fn update_tray(app: &AppHandle, state: &Arc<AppState>) {
    let status = *state.status.lock();
    if let Some(tray) = app.tray_by_id("main") {
        crate::tray::update_status(&tray, status);
    }
}
