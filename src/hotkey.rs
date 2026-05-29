use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::time::Instant;

use tauri::{AppHandle, Emitter};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};

use crate::state::{AppState, AppStatus};

const TAP_LATCH_THRESHOLD_MS: u128 = 350;

/// Register (or re-register) the push-to-talk shortcut.
///
/// Holding the shortcut behaves like push-to-talk. A very short press behaves
/// like a macro tap: it latches recording on, then the next tap stops it.
///
/// Call `app.global_shortcut().unregister(old_hotkey)` before calling this
/// when the hotkey changes — do **not** use `unregister_all()`.
pub fn register_shortcut(app: &AppHandle, state: &Arc<AppState>, hotkey: &str) {
    let state            = Arc::clone(state);
    let app_clone        = app.clone();
    // Tracks whether the physical key is currently held down so OS key-repeat
    // events do not start multiple recording threads.
    let key_held         = Arc::new(AtomicBool::new(false));
    let tap_latched      = Arc::new(AtomicBool::new(false));
    let press_started_at = Arc::new(parking_lot::Mutex::new(None::<Instant>));

    let result = app.global_shortcut().on_shortcut(hotkey, move |_app, _shortcut, event| {
        match event.state {
            ShortcutState::Pressed => {
                // `swap` returns the old value.  If it was already `true` the
                // key is being repeated — skip.
                if key_held.swap(true, Ordering::Relaxed) {
                    return;
                }

                if tap_latched.swap(false, Ordering::Relaxed) {
                    *press_started_at.lock() = None;
                    if stop_recording(&state) {
                        return;
                    }
                }

                if start_recording(&app_clone, &state, "flowey-record") {
                    *press_started_at.lock() = Some(Instant::now());
                }
            }
            ShortcutState::Released => {
                key_held.store(false, Ordering::Relaxed);

                let started_at = press_started_at.lock().take();
                if let Some(started_at) = started_at {
                    if started_at.elapsed().as_millis() < TAP_LATCH_THRESHOLD_MS {
                        tap_latched.store(true, Ordering::Relaxed);
                        log::info!("Recording latched from quick hotkey tap");
                    } else {
                        stop_recording(&state);
                    }
                }
            }
        }
    });

    match result {
        Ok(()) => log::info!("Hotkey registered: {hotkey}"),
        Err(e) => log::error!(
            "Failed to register hotkey '{hotkey}': {e} \
             — check it is not already taken by another app"
        ),
    }
}

// ── Recording handlers ────────────────────────────────────────

pub fn start_recording(app: &AppHandle, state: &Arc<AppState>, thread_name: &'static str) -> bool {
    let mut sig_guard = state.stop_signal.lock();

    if sig_guard.is_some() {
        return false;
    }

    let stop = Arc::new(AtomicBool::new(false));
    *sig_guard = Some(Arc::clone(&stop));
    drop(sig_guard); // release before spawning thread

    let (device_name, max_secs) = {
        let cfg = state.config.read();
        (cfg.input_device.clone(), cfg.max_recording_secs)
    };

    // Remember which app had focus so the paste goes to the right window.
    #[cfg(target_os = "macos")]
    unsafe { crate::transcribe::ffi::flowey_capture_focus(); }

    *state.status.lock() = AppStatus::Recording;
    update_tray(app, state);

    let tx = state.audio_tx.clone();
    let app = app.clone();
    let state = Arc::clone(state);
    std::thread::Builder::new()
        .name(thread_name.into())
        .spawn(move || {
            let sent = match crate::audio::record_until_stopped(
                Arc::clone(&stop),
                device_name.as_deref(),
                max_secs,
            ) {
                Ok(data) => {
                    if let Err(e) = tx.try_send(data) {
                        log::warn!("Pipeline busy, audio dropped: {e}");
                        false
                    } else {
                        true
                    }
                }
                Err(e) => {
                    log::error!("Recording error: {e}");
                    false
                }
            };

            clear_stop_signal_if_current(&state, &stop);

            if !sent {
                *state.status.lock() = AppStatus::Idle;
                update_tray(&app, &state);
            }
        })
        .expect("Failed to spawn recording thread");

    log::info!("Recording started");
    true
}

pub fn stop_recording(state: &Arc<AppState>) -> bool {
    if let Some(sig) = state.stop_signal.lock().take() {
        sig.store(true, Ordering::Relaxed);
        log::info!("Recording stopped");
        true
    } else {
        false
    }
}

fn clear_stop_signal_if_current(state: &Arc<AppState>, stop: &Arc<AtomicBool>) {
    let mut sig_guard = state.stop_signal.lock();
    if sig_guard
        .as_ref()
        .map(|current| Arc::ptr_eq(current, stop))
        .unwrap_or(false)
    {
        sig_guard.take();
    }
}

// ── Tray + event broadcast ────────────────────────────────────

fn update_tray(app: &AppHandle, state: &Arc<AppState>) {
    let status = *state.status.lock();
    if let Some(tray) = app.tray_by_id("main") {
        crate::tray::update_status(&tray, status);
    }
    let _ = app.emit("flowey:status", status);
    // Show / hide the floating overlay pill.
    crate::overlay::update(app, status);
}
