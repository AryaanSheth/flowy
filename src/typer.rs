use anyhow::{Context, Result};

use crate::config::OutputMode;

/// Deliver `text` to the user according to the configured `mode`.
///
/// - `Type`             → simulate keystrokes into the focused window
/// - `Clipboard`        → write to the system clipboard via `pbcopy`
/// - `TypeAndClipboard` → both
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
/// Uses CoreGraphics via `enigo` — requires Accessibility permission
/// (System Settings → Privacy → Accessibility).
fn do_type(text: &str) -> Result<()> {
    #[cfg(not(target_os = "macos"))]
    {
        let _ = text;
        anyhow::bail!("Keystroke injection is only supported on macOS");
    }

    #[cfg(target_os = "macos")]
    {
        use enigo::{Enigo, Keyboard, Settings};

        let mut enigo = Enigo::new(&Settings::default())
            .context("Failed to initialise keystroke injector")?;

        enigo
            .text(text)
            .context("Keystroke injection failed — grant Accessibility permission in System Settings")?;

        log::debug!("Typed {} chars", text.len());
        Ok(())
    }
}

/// Write `text` to the macOS clipboard using the built-in `pbcopy` utility.
///
/// `pbcopy` is part of macOS base; no extra crate required.
fn do_clipboard(text: &str) -> Result<()> {
    use std::io::Write;
    use std::process::{Command, Stdio};

    let mut child = Command::new("pbcopy")
        .stdin(Stdio::piped())
        .spawn()
        .context("Failed to launch pbcopy — is this macOS?")?;

    child
        .stdin
        .take()
        .context("pbcopy stdin unavailable")?
        .write_all(text.as_bytes())
        .context("Failed to write to pbcopy stdin")?;

    let status = child.wait().context("pbcopy did not exit cleanly")?;
    if !status.success() {
        anyhow::bail!("pbcopy exited with status {status}");
    }

    log::debug!("Copied {} chars to clipboard via pbcopy", text.len());
    Ok(())
}
