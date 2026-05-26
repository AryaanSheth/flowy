//! Flowey — minimal local speech-to-text for the desktop.
//!
//! Pipeline overview:
//!
//!   Global hotkey (tauri-plugin-global-shortcut)
//!     Key down  ──► spawn OS thread: record_until_stopped()
//!     Key up    ──► store(true, AtomicBool)  → thread stops
//!                           │
//!                   std::sync::mpsc  (try_send, non-blocking)
//!                           │
//!             Background thread: pipeline_loop()
//!               ① resample to 16 kHz mono   (rubato)
//!               ② transcribe                 (whisper-rs)
//!               ③ apply dictionary
//!               ④ deliver text               (enigo / clipboard)

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod audio;
mod commands;
mod config;
mod dictionary;
mod hotkey;
mod resample;
mod state;
mod transcribe;
mod tray;
mod typer;

use std::sync::{mpsc, Arc};

use transcribe::Transcriber;

use crate::state::{AppState, AppStatus, AudioData};

fn main() {
    env_logger::Builder::from_default_env()
        .filter_level(log::LevelFilter::Info)
        .init();

    let config = config::Config::load();

    // Bounded channel: capacity 8 gives comfortable back-pressure without
    // blocking the recording thread for more than one pending transcript.
    let (audio_tx, audio_rx) = mpsc::sync_channel::<AudioData>(8);

    let state = Arc::new(AppState::new(config, audio_tx));

    // Spawn the pipeline thread BEFORE app.run() (which blocks).
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
            // Store handle so the pipeline thread can update the tray.
            *state.app_handle.lock() = Some(app.handle().clone());

            // Build tray.
            tray::build(app.handle())?;

            // Preload Whisper model if a path is already saved.
            let model_path = state.config.read().model_path.clone();
            if !model_path.is_empty() {
                match Transcriber::load(&model_path) {
                    Ok(t) => *state.transcriber.lock() = Some(t),
                    Err(e) => log::warn!("Could not preload model: {e}"),
                }
            } else {
                log::info!("No model path configured — open Settings to set one");
            }

            // Register PTT hotkey.
            let hotkey = state.config.read().hotkey.clone();
            hotkey::register_shortcut(app.handle(), &state, &hotkey);

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_config,
            commands::save_config,
            commands::get_status,
            commands::get_history,
            commands::clear_history,
            commands::list_audio_devices,
            commands::browse_model_file,
            commands::test_dictionary,
        ])
        .on_window_event(|win, event| {
            // Hide the settings window instead of destroying it — re-opening
            // is instant and the JS state is preserved.
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

        // Check model loaded BEFORE flipping the tray to "Transcribing" so
        // the user is not confused by a spinner that immediately does nothing.
        let has_model = state.transcriber.lock().is_some();
        if !has_model {
            log::warn!("No Whisper model loaded — open Settings to configure one");
            reset_status(&state);
            continue;
        }

        // ── Status: Transcribing ─────────────────────────────
        *state.status.lock() = AppStatus::Transcribing;
        update_tray(&state);

        // ── 1. Resample ──────────────────────────────────────
        let samples_16k = match resample::to_16khz_mono(&raw_samples, sample_rate, channels) {
            Ok(s) => s,
            Err(e) => {
                log::error!("Resample error: {e}");
                reset_status(&state);
                continue;
            }
        };

        // ── 2. Transcribe ────────────────────────────────────
        let (language, dict, history_size) = {
            let cfg = state.config.read();
            (cfg.language.clone(), cfg.dictionary.clone(), cfg.history_size)
        };

        let text = {
            // Use try_lock with a fallback to avoid deadlock if model reload
            // is happening concurrently.
            match state.transcriber.lock().as_ref() {
                None => { reset_status(&state); continue; }
                Some(t) => match t.transcribe(&samples_16k, &language) {
                    Ok(s) => s,
                    Err(e) => {
                        log::error!("Transcription error: {e}");
                        String::new()
                    }
                },
            }
        };

        if text.is_empty() {
            reset_status(&state);
            continue;
        }

        // ── 3. Dictionary ────────────────────────────────────
        let text = dictionary::apply(&text, &dict);
        log::info!("Transcribed: {:?}", text);

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
    update_tray(state);
}

fn update_tray(state: &AppState) {
    let status = *state.status.lock();
    if let Some(handle) = state.app_handle.lock().as_ref() {
        if let Some(tray) = handle.tray_by_id("main") {
            tray::update_status(&tray, status);
        }
    }
}
