use anyhow::{Context, Result};

use crate::config::OutputMode;

/// Deliver `text` to the user according to the configured `mode`.
///
/// - `Type`             → clipboard + Cmd+V into the focused window
/// - `Clipboard`        → write to the system clipboard only (no paste)
/// - `TypeAndClipboard` → clipboard + Cmd+V (clipboard stays populated)
pub fn output_text(text: &str, mode: OutputMode) -> Result<()> {
    if text.is_empty() {
        return Ok(());
    }
    match mode {
        OutputMode::Type             => do_type(text),
        OutputMode::Clipboard        => do_clipboard(text),
        // TypeAndClipboard: do_type already leaves the text on the clipboard,
        // so a separate do_clipboard call isn't strictly needed, but we call it
        // first so the clipboard is populated even if the paste step fails.
        OutputMode::TypeAndClipboard => {
            do_clipboard(text)?;
            do_type(text)
        }
    }
}

/// Inject `text` into whatever window currently has focus.
///
/// Uses the `flowey_type_text` ObjC shim which:
///   1. Writes the text to NSPasteboard.
///   2. Posts a Cmd+V key pair via CGEventPost.
///
/// Requires Accessibility permission (System Settings → Privacy → Accessibility).
fn do_type(text: &str) -> Result<()> {
    #[cfg(not(target_os = "macos"))]
    {
        let _ = text;
        anyhow::bail!("Keystroke injection is only supported on macOS");
    }

    #[cfg(target_os = "macos")]
    {
        use std::ffi::CString;

        let c_text = CString::new(text).context("Text contains interior null bytes")?;

        let result = unsafe { crate::transcribe::ffi::flowey_type_text(c_text.as_ptr()) };

        if result == 0 {
            anyhow::bail!(
                "Keystroke injection failed — ensure Flowey has \
                 Accessibility permission in System Settings → Privacy & Security → Accessibility"
            );
        }

        log::debug!("Injected {} chars via clipboard+Cmd+V", text.len());
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
