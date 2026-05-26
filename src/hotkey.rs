use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

use tauri::{AppHandle, Emitter};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};

use crate::state::{AppState, AppStatus};

/// Register (or re-register) the toggle-to-talk shortcut.
///
/// First press starts recording; a second press stops it.
/// Key-repeat events are ignored so holding the key down does nothing.
///
/// Call `app.global_shortcut().unregister(old_hotkey)` before calling this
/// when the hotkey changes — do **not** use `unregister_all()`.
pub fn register_shortcut(app: &AppHandle, state: &Arc<AppState>, hotkey: &str) {
    let state     = Arc::clone(state);
    let app_clone = app.clone();
    // Tracks whether the physical key is currently held down so OS key-repeat
    // events don't fire multiple toggles.
    let key_held  = Arc::new(AtomicBool::new(false));

    let result = app.global_shortcut().on_shortcut(hotkey, move |_app, _shortcut, event| {
        match event.state {
            ShortcutState::Pressed => {
                // `swap` returns the old value.  If it was already `true` the
                // key is being repeated — skip.
                if key_held.swap(true, Ordering::Relaxed) {
                    return;
                }
                on_toggle(&app_clone, &state);
            }
            ShortcutState::Released => {
                key_held.store(false, Ordering::Relaxed);
            }
        }
    });

    match result {
        Ok(()) => log::info!("Hotkey registered (toggle mode): {hotkey}"),
        Err(e) => log::error!(
            "Failed to register hotkey '{hotkey}': {e} \
             — check it is not already taken by another app"
        ),
    }
}

// ── Toggle handler ────────────────────────────────────────────

fn on_toggle(app: &AppHandle, state: &Arc<AppState>) {
    let mut sig_guard = state.stop_signal.lock();

    if let Some(sig) = sig_guard.take() {
        // ── Already recording → stop ─────────────────────────
        sig.store(true, Ordering::Relaxed);
        log::info!("Recording toggled off");
        // Status will flip: Recording → Transcribing → Idle
        // as the pipeline processes and delivers the audio.
    } else {
        // ── Not recording → start ────────────────────────────
        let stop = Arc::new(AtomicBool::new(false));
        *sig_guard = Some(Arc::clone(&stop));
        drop(sig_guard); // release before spawning thread

        let (device_name, max_secs) = {
            let cfg = state.config.read();
            (cfg.input_device.clone(), cfg.max_recording_secs)
        };

        *state.status.lock() = AppStatus::Recording;
        update_tray(app, state);

        let tx = state.audio_tx.clone();
        std::thread::Builder::new()
            .name("flowey-record".into())
            .spawn(move || {
                match crate::audio::record_until_stopped(stop, device_name.as_deref(), max_secs) {
                    Ok(data) => {
                        if let Err(e) = tx.try_send(data) {
                            log::warn!("Pipeline busy, audio dropped: {e}");
                        }
                    }
                    Err(e) => log::error!("Recording error: {e}"),
                }
            })
            .expect("Failed to spawn recording thread");

        log::info!("Recording toggled on");
    }
}

// ── Tray + event broadcast ────────────────────────────────────

fn update_tray(app: &AppHandle, state: &Arc<AppState>) {
    let status = *state.status.lock();
    if let Some(tray) = app.tray_by_id("main") {
        crate::tray::update_status(&tray, status);
    }
    let _ = app.emit("flowey:status", status);
}
