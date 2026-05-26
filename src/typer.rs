use anyhow::{Context, Result};

use crate::config::OutputMode;

/// Deliver `text` to the user according to the configured `mode`.
///
/// - `Type`            → simulate keystrokes into the focused window (enigo)
/// - `Clipboard`       → write to the system clipboard (arboard)
/// - `TypeAndClipboard`→ both
///
/// Platform notes are documented on [`do_type`] and [`do_clipboard`].
pub fn output_text(text: &str, mode: OutputMode) -> Result<()> {
    if text.is_empty() {
        return Ok(());
    }
    match mode {
        OutputMode::Type             => do_type(text),
        OutputMode::Clipboard        => do_clipboard(text),
        OutputMode::TypeAndClipboard => {
            // Copy first so the text is on the clipboard even if typing fails.
            do_clipboard(text)?;
            do_type(text)
        }
    }
}

/// Inject `text` as keystrokes into whatever window has focus.
///
/// **macOS**: requires Accessibility permission (System Settings →
/// Privacy → Accessibility).  Without it this is a silent no-op.
/// **Linux/X11**: works; on pure Wayland sessions needs `uinput` or `ydotool`.
/// **Windows**: blocked for UAC-elevated target windows.
fn do_type(text: &str) -> Result<()> {
    use enigo::{Enigo, Keyboard, Settings};

    let mut enigo = Enigo::new(&Settings::default())
        .context("Failed to initialise keystroke injector (enigo)")?;

    enigo
        .text(text)
        .context("Keystroke injection failed — check platform permissions (see README)")?;

    log::debug!("Typed {} chars", text.len());
    Ok(())
}

/// Write `text` to the system clipboard using arboard.
fn do_clipboard(text: &str) -> Result<()> {
    arboard::Clipboard::new()
        .context("Failed to open clipboard")?
        .set_text(text.to_string())
        .context("Failed to write to clipboard")?;

    log::debug!("Copied {} chars to clipboard", text.len());
    Ok(())
}
