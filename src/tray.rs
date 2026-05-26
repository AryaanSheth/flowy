use tauri::{
    image::Image,
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, Runtime,
};

use crate::state::AppStatus;

// Embed tray icons at compile time.
const ICON_IDLE:         &[u8] = include_bytes!("../icons/tray-idle.png");
const ICON_RECORDING:    &[u8] = include_bytes!("../icons/tray-recording.png");
const ICON_TRANSCRIBING: &[u8] = include_bytes!("../icons/tray-transcribing.png");

/// Build and register the system-tray icon with its right-click menu.
pub fn build<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<TrayIcon<R>> {
    let settings_item = MenuItem::with_id(app, "settings", "Settings", true, None::<&str>)?;
    let separator     = tauri::menu::PredefinedMenuItem::separator(app)?;
    let quit_item     = MenuItem::with_id(app, "quit",     "Quit",     true, None::<&str>)?;

    let menu = Menu::with_items(app, &[&settings_item, &separator, &quit_item])?;

    let icon = Image::from_bytes(ICON_IDLE)?;

    TrayIconBuilder::with_id("main")
        .icon(icon)
        .menu(&menu)
        .tooltip("Flowey — Idle\nHold hotkey to record")
        .show_menu_on_left_click(false)
        // Left-click toggles the settings window
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                let app = tray.app_handle();
                toggle_settings_window(app);
            }
        })
        .on_menu_event(|app, event| match event.id.as_ref() {
            "settings" => toggle_settings_window(app),
            "quit" => {
                log::info!("Quitting Flowey");
                app.exit(0);
            }
            _ => {}
        })
        .build(app)
}

/// Show the settings window if hidden; bring it to front if already visible.
/// Called from both left-click tray event and the "Settings" menu item.
pub fn toggle_settings_window<R: Runtime>(app: &AppHandle<R>) {
    if let Some(win) = app.get_webview_window("settings") {
        let visible = win.is_visible().unwrap_or(false);
        if visible {
            // Already open — just focus it
            let _ = win.set_focus();
        } else {
            let _ = win.show();
            let _ = win.set_focus();
        }
    } else {
        log::error!("Settings window not found");
    }
}

/// Update the tray icon and tooltip to reflect the current pipeline status.
pub fn update_status<R: Runtime>(tray: &TrayIcon<R>, status: AppStatus) {
    let (icon_bytes, tooltip) = match status {
        AppStatus::Idle         => (ICON_IDLE,         "Flowey — Idle"),
        AppStatus::Recording    => (ICON_RECORDING,    "Flowey — Recording…"),
        AppStatus::Transcribing => (ICON_TRANSCRIBING, "Flowey — Transcribing…"),
    };

    if let Ok(img) = Image::from_bytes(icon_bytes) {
        let _ = tray.set_icon(Some(img));
    }
    let _ = tray.set_tooltip(Some(tooltip));
}
