//! Flowey — minimal local speech-to-text for the desktop.
//!
//! Architecture:
//!   ┌─────────────────────────────────────────────────────────────┐
//!   │  Global hotkey (tauri-plugin-global-shortcut)               │
//!   │  Key down  ──► spawn recording thread                       │
//!   │  Key up    ──► signal stop (AtomicBool)                     │
//!   └───────────────────────┬─────────────────────────────────────┘
//!                           │ std::sync::mpsc (AudioData)
//!   ┌───────────────────────▼─────────────────────────────────────┐
//!   │  Pipeline thread (std::thread)                              │
//!   │  1. Resample to 16 kHz mono (rubato)                        │
//!   │  2. Transcribe (whisper-rs / whisper.cpp)                   │
//!   │  3. Apply custom dictionary substitutions                   │
//!   │  4. Inject text into focused window (enigo)                 │
//!   └─────────────────────────────────────────────────────────────┘

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

    // Channel connecting the recording thread → pipeline thread.
    let (audio_tx, audio_rx) = mpsc::sync_channel::<AudioData>(4);

    let state = Arc::new(AppState::new(config, audio_tx));

    // Spawn the pipeline thread *before* calling app.run() (which blocks).
    let pipeline_state = Arc::clone(&state);
    std::thread::Builder::new()
        .name("flowey-pipeline".into())
        .spawn(move || pipeline_loop(audio_rx, pipeline_state))
        .expect("Failed to spawn pipeline thread");

    // Build and run the Tauri application.
    tauri::Builder::default()
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .manage(Arc::clone(&state))
        .setup(move |app| {
            // Store the app handle so the pipeline thread can update the tray.
            *state.app_handle.lock() = Some(app.handle().clone());

            // Build the system tray icon + menu.
            tray::build(app.handle())?;

            // Load Whisper model if a path is already configured.
            let model_path = state.config.read().model_path.clone();
            if !model_path.is_empty() {
                match Transcriber::load(&model_path) {
                    Ok(t) => *state.transcriber.lock() = Some(t),
                    Err(e) => log::warn!("Could not load model on startup: {e}"),
                }
            } else {
                log::info!("No model path configured — open Settings to set one.");
            }

            // Register the push-to-talk hotkey.
            let hotkey = state.config.read().hotkey.clone();
            hotkey::register_shortcut(app.handle(), &state, &hotkey);

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_config,
            commands::save_config,
            commands::get_status,
            commands::test_dictionary,
            commands::browse_model_file,
        ])
        .on_window_event(|win, event| {
            // Hide settings window on close instead of destroying it,
            // so re-opening it is instant.
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

// ---------------------------------------------------------------------------
// Background pipeline thread
// ---------------------------------------------------------------------------

fn pipeline_loop(rx: mpsc::Receiver<AudioData>, state: Arc<AppState>) {
    log::info!("Pipeline thread started");

    while let Ok((raw_samples, sample_rate, channels)) = rx.recv() {
        // --- 1. Resample ---
        *state.status.lock() = AppStatus::Transcribing;
        update_tray(&state);

        let samples_16k = match resample::to_16khz_mono(&raw_samples, sample_rate, channels) {
            Ok(s) => s,
            Err(e) => {
                log::error!("Resample error: {e}");
                reset_status(&state);
                continue;
            }
        };

        // --- 2. Transcribe ---
        let (language, dict) = {
            let cfg = state.config.read();
            (cfg.language.clone(), cfg.dictionary.clone())
        };

        let text = {
            let guard = state.transcriber.lock();
            match guard.as_ref() {
                None => {
                    log::warn!("No Whisper model loaded — open Settings to configure one");
                    String::new()
                }
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

        // --- 3. Custom dictionary ---
        let text = dictionary::apply(&text, &dict);
        log::info!("Transcribed: {:?}", text);

        // --- 4. Inject text ---
        if let Err(e) = typer::type_text(&text) {
            log::error!("Text injection failed: {e}");
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
