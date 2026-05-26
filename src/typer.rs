use anyhow::{Context, Result};
use enigo::{Enigo, Keyboard, Settings};

/// Type `text` into whatever window currently has keyboard focus.
///
/// Uses `enigo` for cross-platform key injection.
///
/// **Platform notes:**
/// - **macOS**: requires Accessibility permission (System Settings → Privacy → Accessibility).
///   Without it, `enigo::text()` is a silent no-op.
/// - **Linux/Wayland**: `enigo` works on X11; on pure Wayland sessions with no
///   `uinput` access it may fail. The error is surfaced in the log.
/// - **Windows**: blocked by UAC-elevated target windows; otherwise works fine.
pub fn type_text(text: &str) -> Result<()> {
    if text.is_empty() {
        return Ok(());
    }

    let mut enigo = Enigo::new(&Settings::default())
        .context("Failed to initialise Enigo text injector")?;

    enigo
        .text(text)
        .context("Enigo failed to inject text — check platform permissions")?;

    log::debug!("Typed {} chars", text.len());
    Ok(())
}
