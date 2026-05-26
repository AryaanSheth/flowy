use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

use anyhow::{anyhow, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

// ── Device listing ────────────────────────────────────────────

/// Returns the names of all available audio input devices.
/// The first entry is always an empty string meaning "system default".
pub fn list_input_devices() -> Vec<String> {
    let host = cpal::default_host();
    let named: Vec<String> = host
        .input_devices()
        .map(|iter| iter.filter_map(|d| d.name().ok()).collect())
        .unwrap_or_default();
    // Empty string = default device (shown as "System default" in the UI)
    std::iter::once(String::new()).chain(named).collect()
}

// ── Recording ─────────────────────────────────────────────────

/// Records from an input device until `stop` is set **or** `max_secs` elapses.
///
/// `device_name` — name of the device to use, or `None` / `""` for the system
/// default.  Falls back to the system default if the named device is not found.
///
/// Returns `(samples_f32_interleaved, sample_rate_hz, channel_count)`.
pub fn record_until_stopped(
    stop: Arc<AtomicBool>,
    device_name: Option<&str>,
    max_secs: u32,
) -> Result<(Vec<f32>, u32, u16)> {
    let host = cpal::default_host();

    // Resolve device.
    let device = resolve_device(&host, device_name)?;
    let device_name_log = device.name().unwrap_or_else(|_| "?".into());

    let supported  = device.default_input_config()?;
    let sample_rate = supported.sample_rate().0;
    let channels    = supported.channels();
    let fmt         = supported.sample_format();
    let stream_cfg: cpal::StreamConfig = supported.into();

    // Shared sample buffer — written inside cpal callback, read once done.
    let buf: Arc<parking_lot::Mutex<Vec<f32>>> = Arc::new(parking_lot::Mutex::new(
        Vec::with_capacity(sample_rate as usize * max_secs.min(60) as usize),
    ));

    // If the audio stream itself errors, trigger the stop flag so the spin
    // loop below wakes up and returns rather than hanging forever.
    let stop_on_err = Arc::clone(&stop);

    let stream = build_stream(&device, &stream_cfg, fmt, Arc::clone(&buf), stop_on_err)?;
    stream.play()?;

    log::debug!(
        "Recording started: device='{device_name_log}', {sample_rate} Hz, \
         {channels}ch, {fmt:?}, max={max_secs}s"
    );

    // Spin until stop flag or timeout.
    let deadline = std::time::Instant::now()
        + std::time::Duration::from_secs(max_secs as u64);

    while !stop.load(Ordering::Relaxed) {
        if std::time::Instant::now() >= deadline {
            log::warn!("Max recording duration ({max_secs}s) reached — stopping automatically");
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }

    drop(stream); // stops cpal callbacks; waits for in-flight callback to finish
    let samples = buf.lock().clone();
    log::debug!("Recording stopped: {} samples", samples.len());

    Ok((samples, sample_rate, channels))
}

// ── Helpers ───────────────────────────────────────────────────

fn resolve_device(
    host: &cpal::Host,
    name: Option<&str>,
) -> Result<cpal::Device> {
    let want = name.unwrap_or("").trim();

    if !want.is_empty() {
        if let Ok(mut iter) = host.input_devices() {
            if let Some(d) = iter.find(|d| d.name().map(|n| n == want).unwrap_or(false)) {
                return Ok(d);
            }
        }
        log::warn!("Device '{want}' not found, falling back to system default");
    }

    host.default_input_device()
        .ok_or_else(|| anyhow!("No input device found — is a microphone connected?"))
}

fn build_stream(
    device: &cpal::Device,
    cfg: &cpal::StreamConfig,
    fmt: cpal::SampleFormat,
    buf: Arc<parking_lot::Mutex<Vec<f32>>>,
    stop_on_err: Arc<AtomicBool>,
) -> Result<cpal::Stream> {
    let stream = match fmt {
        cpal::SampleFormat::F32 => {
            let b = Arc::clone(&buf);
            device.build_input_stream(
                cfg,
                move |data: &[f32], _| b.lock().extend_from_slice(data),
                move |e| {
                    log::error!("Audio stream error: {e}");
                    stop_on_err.store(true, Ordering::Relaxed);
                },
                None,
            )?
        }
        cpal::SampleFormat::I16 => {
            let b = Arc::clone(&buf);
            // Fix: divide by i16::MAX + 1 to keep range symmetric [-1.0, 1.0)
            device.build_input_stream(
                cfg,
                move |data: &[i16], _| {
                    b.lock().extend(
                        data.iter()
                            .map(|&s| s as f32 / (i16::MAX as f32 + 1.0)),
                    )
                },
                move |e| {
                    log::error!("Audio stream error: {e}");
                    stop_on_err.store(true, Ordering::Relaxed);
                },
                None,
            )?
        }
        cpal::SampleFormat::U16 => {
            let b = Arc::clone(&buf);
            device.build_input_stream(
                cfg,
                move |data: &[u16], _| {
                    b.lock().extend(
                        data.iter()
                            .map(|&s| s as f32 / u16::MAX as f32 * 2.0 - 1.0),
                    )
                },
                move |e| {
                    log::error!("Audio stream error: {e}");
                    stop_on_err.store(true, Ordering::Relaxed);
                },
                None,
            )?
        }
        other => return Err(anyhow!("Unsupported sample format: {other:?}")),
    };
    Ok(stream)
}
