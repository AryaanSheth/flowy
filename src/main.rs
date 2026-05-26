//! Flowey — minimal push-to-talk speech-to-text for macOS.
//!
//! Pipeline overview:
//!
//!   Global hotkey (tauri-plugin-global-shortcut)
//!     Key press  ──► spawn OS thread: record_until_stopped()
//!     Key press  ──► stop signal → thread stops, sends audio
//!                           │
//!                   std::sync::mpsc  (bounded, capacity 8)
//!                           │
//!             Background thread: pipeline_loop()
//!               ① downmix to mono + write WAV
//!               ② SFSpeechRecognizer (macOS native)
//!               ③ apply dictionary
//!               ④ Ollama enhancement (optional)
//!               ⑤ deliver text (keystrokes / clipboard)

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod audio;
mod commands;
mod config;
mod dictionary;
mod hotkey;
mod ollama;
mod state;
mod transcribe;
mod tray;
mod typer;

use std::sync::{mpsc, Arc};

use tauri::Emitter;

use crate::state::{AppState, AppStatus, AudioData};

fn main() {
    env_logger::Builder::from_default_env()
        .filter_level(log::LevelFilter::Info)
        .init();

    let config = config::Config::load();

    let (audio_tx, audio_rx) = mpsc::sync_channel::<AudioData>(8);

    let state = Arc::new(AppState::new(config, audio_tx));

    // Spawn pipeline thread BEFORE app.run() blocks.
    let pipeline_state = Arc::clone(&state);
    std::thread::Builder::new()
        .name("flowey-pipeline".into())
        .spawn(move || pipeline_loop(audio_rx, pipeline_state))
        .expect("Failed to spawn pipeline thread");

    tauri::Builder::default()
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(tauri_plugin_dialog::init())
        .manage(Arc::clone(&state))
        .setup(move |app| {
            *state.app_handle.lock() = Some(app.handle().clone());

            tray::build(app.handle())?;

            // Request speech recognition permission — shows system dialog on
            // first run; subsequent calls are no-ops handled by the OS.
            transcribe::request_authorization();

            // Register the PTT hotkey.
            let hotkey = state.config.read().hotkey.clone();
            hotkey::register_shortcut(app.handle(), &state, &hotkey);

            // Request Accessibility so CGEventTap (used by global-shortcut)
            // can receive events.  This opens System Settings → Accessibility
            // and highlights this process if not already trusted.
            if !transcribe::request_accessibility() {
                log::warn!(
                    "Accessibility not granted — global hotkey will not fire. \
                     Grant access in System Settings → Privacy & Security → Accessibility."
                );
            }

            tray::toggle_settings_window(app.handle());

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_config,
            commands::save_config,
            commands::get_status,
            commands::get_history,
            commands::clear_history,
            commands::list_audio_devices,
            commands::test_dictionary,
            commands::check_ollama,
            commands::start_recording,
            commands::stop_recording,
            commands::check_permissions,
        ])
        .on_window_event(|win, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                if win.label() == "settings" {
                    api.prevent_close();
                    let _ = win.hide();
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running Flowey");
}

// ── Pipeline thread ───────────────────────────────────────────

fn pipeline_loop(rx: mpsc::Receiver<AudioData>, state: Arc<AppState>) {
    log::info!("Pipeline thread started");

    while let Ok((raw_samples, sample_rate, channels)) = rx.recv() {
        let output_mode = state.config.read().output_mode;

        // ── Status: Transcribing ─────────────────────────────
        *state.status.lock() = AppStatus::Transcribing;
        broadcast_status(&state);

        // ── 1. Transcribe via macOS Speech framework ─────────
        if !transcribe::is_authorized() {
            log::warn!(
                "Speech recognition not authorized — open System Settings → \
                 Privacy & Security → Speech Recognition and enable Flowey"
            );
            reset_status(&state);
            continue;
        }

        let text = match transcribe::transcribe(&raw_samples, sample_rate, channels) {
            Ok(t)  => t,
            Err(e) => {
                log::error!("Transcription error: {e}");
                reset_status(&state);
                continue;
            }
        };

        if text.is_empty() {
            log::debug!("Transcription produced no text (silence?)");
            reset_status(&state);
            continue;
        }

        // ── 2. Dictionary ────────────────────────────────────
        let (dict, history_size) = {
            let cfg = state.config.read();
            (cfg.dictionary.clone(), cfg.history_size)
        };
        let text = dictionary::apply(&text, &dict);
        log::info!("Transcribed: {:?}", text);

        // ── 3. Ollama enhancement (optional) ─────────────────
        let text = {
            let cfg = state.config.read();
            if cfg.ollama_enabled && !text.is_empty() {
                let endpoint = cfg.ollama_endpoint.clone();
                let model    = cfg.ollama_model.clone();
                let prompt   = cfg.ollama_prompt.clone();
                drop(cfg);
                match ollama::enhance(&endpoint, &model, &prompt, &text) {
                    Ok(enhanced) if !enhanced.is_empty() => {
                        log::info!("Enhanced: {:?}", enhanced);
                        enhanced
                    }
                    Ok(_)  => text,
                    Err(e) => {
                        log::warn!("Ollama enhancement failed, using raw text: {e}");
                        text
                    }
                }
            } else {
                text
            }
        };

        // ── 4. Store in history ──────────────────────────────
        {
            let mut hist = state.history.lock();
            hist.push_front(text.clone());
            while hist.len() > history_size {
                hist.pop_back();
            }
        }

        // ── 5. Deliver text ──────────────────────────────────
        if let Err(e) = typer::output_text(&text, output_mode) {
            log::error!("Text delivery failed: {e}");
        }

        reset_status(&state);
    }

    log::info!("Pipeline thread exiting");
}

fn reset_status(state: &AppState) {
    *state.status.lock() = AppStatus::Idle;
    broadcast_status(state);
}

/// Update the tray icon AND push an instant `status` event to the frontend.
fn broadcast_status(state: &AppState) {
    let status = *state.status.lock();
    if let Some(handle) = state.app_handle.lock().as_ref() {
        if let Some(tray) = handle.tray_by_id("main") {
            tray::update_status(&tray, status);
        }
        // Push directly to the settings window — no 1.5 s polling lag.
        let _ = handle.emit("flowey:status", status);
    }
}
