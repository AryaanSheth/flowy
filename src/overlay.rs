//! Floating recording-indicator overlay.
//!
//! A small transparent pill window that appears at the top-centre of the
//! primary monitor while recording or transcribing, then fades out and hides
//! when the pipeline returns to Idle.
//!
//! The visual animations (slide-in, waveform bars, colour transitions) are
//! handled entirely in `frontend/overlay.html` via CSS + `flowey:status`
//! events.  This module only manages OS-level window visibility and position.

use tauri::{AppHandle, Manager, Runtime};

use crate::state::AppStatus;

/// Logical width of the overlay window (must match `tauri.conf.json`).
const OVERLAY_W: f64 = 220.0;

/// Update the overlay window in response to a pipeline-status change.
pub fn update<R: Runtime>(app: &AppHandle<R>, status: AppStatus) {
    let Some(win) = app.get_webview_window("overlay") else { return };

    match status {
        AppStatus::Recording => {
            // Re-centre the pill at the top of the primary monitor every time
            // recording starts (the user might have changed display layout).
            centre_at_top(app, &win);
            let _ = win.set_always_on_top(true);
            let _ = win.show();
        }

        AppStatus::Transcribing => {
            // Stay visible; the JS overlay updates its own visuals from the
            // `flowey:status` event that was already emitted by the caller.
        }

        AppStatus::Idle => {
            // Let the CSS exit-animation run (~180 ms) before hiding the window.
            let win = win.clone();
            std::thread::Builder::new()
                .name("flowey-overlay-hide".into())
                .spawn(move || {
                    std::thread::sleep(std::time::Duration::from_millis(350));
                    let _ = win.hide();
                })
                .ok();
        }
    }
}

// ── Helpers ───────────────────────────────────────────────────────

/// Position the overlay window horizontally centred and vertically just below
/// the menu bar of the primary monitor.
fn centre_at_top<R: Runtime>(app: &AppHandle<R>, win: &tauri::WebviewWindow<R>) {
    let Ok(Some(monitor)) = app.primary_monitor() else { return };

    let sf       = monitor.scale_factor();
    let screen_w = monitor.size().width  as f64 / sf;
    let screen_x = monitor.position().x  as f64 / sf;

    let x = screen_x + (screen_w - OVERLAY_W) / 2.0;
    let y = 28.0_f64; // below the macOS menu bar

    let _ = win.set_position(tauri::LogicalPosition::new(x, y));
}
