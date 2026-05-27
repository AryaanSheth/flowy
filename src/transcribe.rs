//! macOS SFSpeechRecognizer-based transcription.
//!
//! Pipeline:
//!   Vec<f32> (interleaved, device sample rate)
//!     → downmix to mono
//!     → write 32-bit float WAV to /tmp
//!     → SFSpeechRecognizer (file-based recognition via speech.m C shim)
//!     → delete temp file
//!     → String

use anyhow::{anyhow, Context, Result};

// ── C shim declarations ───────────────────────────────────────

#[cfg(target_os = "macos")]
pub mod ffi {
    use std::ffi::c_char;
    extern "C" {
        pub fn flowey_request_speech_auth();
        pub fn flowey_speech_is_authorized() -> std::ffi::c_int;
        pub fn flowey_transcribe(wav_path: *const c_char) -> *mut c_char;
        pub fn flowey_free_str(s: *mut c_char);
        /// Prompt the user to grant Accessibility access (needed for global hotkeys).
        /// Returns 1 if already trusted, 0 if a dialog was shown.
        pub fn flowey_request_accessibility() -> std::ffi::c_int;
        /// Returns 1 if Accessibility is currently granted.
        pub fn flowey_is_accessibility_trusted() -> std::ffi::c_int;
        /// Deliver text to the focused window via clipboard + Cmd+V.
        /// Returns 1 on success, 0 on failure.
        pub fn flowey_type_text(text: *const c_char) -> std::ffi::c_int;
        /// Save the currently-frontmost application so we can re-focus it
        /// after transcription (call just before recording starts).
        pub fn flowey_capture_focus();
    }
}

// ── Public API ────────────────────────────────────────────────

/// Trigger the macOS speech-recognition permission dialog.
pub fn request_authorization() {
    #[cfg(target_os = "macos")]
    unsafe { ffi::flowey_request_speech_auth(); }
}

/// Check whether speech recognition is currently authorized.
pub fn is_authorized() -> bool {
    #[cfg(target_os = "macos")]
    { unsafe { ffi::flowey_speech_is_authorized() == 1 } }
    #[cfg(not(target_os = "macos"))]
    false
}

/// Prompt the user to grant Accessibility access in System Settings.
/// Returns true if already trusted (no dialog shown).
pub fn request_accessibility() -> bool {
    #[cfg(target_os = "macos")]
    { unsafe { ffi::flowey_request_accessibility() == 1 } }
    #[cfg(not(target_os = "macos"))]
    true
}

/// Check whether Accessibility is currently granted.
pub fn is_accessibility_trusted() -> bool {
    #[cfg(target_os = "macos")]
    { unsafe { ffi::flowey_is_accessibility_trusted() == 1 } }
    #[cfg(not(target_os = "macos"))]
    true
}

/// Transcribe `samples` (interleaved f32 PCM at `sample_rate` Hz, `channels` ch)
/// using the macOS Speech framework.  Returns the recognized text.
pub fn transcribe(samples: &[f32], sample_rate: u32, channels: u16) -> Result<String> {
    if samples.is_empty() {
        return Ok(String::new());
    }

    // ── 1. Downmix to mono ───────────────────────────────────
    let mono: Vec<f32> = if channels == 1 {
        samples.to_vec()
    } else {
        let ch = channels as usize;
        samples
            .chunks_exact(ch)
            .map(|frame| frame.iter().sum::<f32>() / ch as f32)
            .collect()
    };

    // ── 2. Write 32-bit float WAV to a temp file ─────────────
    let path = std::env::temp_dir().join(format!(
        "flowey_{}.wav",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis()
    ));

    {
        // SFSpeechRecognizer works best with 16-bit signed PCM.
        let spec = hound::WavSpec {
            channels:        1,
            sample_rate,
            bits_per_sample: 16,
            sample_format:   hound::SampleFormat::Int,
        };
        let mut w = hound::WavWriter::create(&path, spec)
            .context("Failed to create temp WAV file")?;
        for &s in &mono {
            let s16 = (s.clamp(-1.0, 1.0) * i16::MAX as f32) as i16;
            w.write_sample(s16).context("Failed to write WAV sample")?;
        }
        w.finalize().context("Failed to finalize WAV file")?;
    }

    // ── 3. Transcribe via macOS Speech framework ─────────────
    let result = do_transcribe(&path);
    let _ = std::fs::remove_file(&path); // best-effort cleanup
    result
}

// ── Internal ──────────────────────────────────────────────────

#[cfg(target_os = "macos")]
fn do_transcribe(path: &std::path::Path) -> Result<String> {
    use std::ffi::{CStr, CString};

    let c_path = CString::new(
        path.to_str().ok_or_else(|| anyhow!("temp path contains non-UTF-8 chars"))?,
    )?;

    unsafe {
        let ptr = ffi::flowey_transcribe(c_path.as_ptr());
        if ptr.is_null() {
            return Err(anyhow!(
                "Speech recognition failed — ensure Flowey has \
                 microphone + speech recognition permission in \
                 System Settings → Privacy"
            ));
        }
        let text = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        ffi::flowey_free_str(ptr);
        Ok(text)
    }
}

#[cfg(not(target_os = "macos"))]
fn do_transcribe(_path: &std::path::Path) -> Result<String> {
    Err(anyhow!("Speech recognition is only supported on macOS"))
}
