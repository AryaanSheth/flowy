use std::sync::{atomic::{AtomicBool, Ordering}, Arc};

use anyhow::{anyhow, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

/// Records from the default input device until `stop` is set to `true`.
///
/// Returns `(samples_f32, sample_rate_hz, channel_count)`.
pub fn record_until_stopped(stop: Arc<AtomicBool>) -> Result<(Vec<f32>, u32, u16)> {
    let host = cpal::default_host();

    let device = host
        .default_input_device()
        .ok_or_else(|| anyhow!("No input device found — is a microphone connected?"))?;

    let supported = device.default_input_config()?;
    let sample_rate = supported.sample_rate().0;
    let channels   = supported.channels();
    let fmt        = supported.sample_format();
    let stream_cfg: cpal::StreamConfig = supported.into();

    // Shared buffer; written inside the cpal callback, read once the stream stops.
    let buf: Arc<parking_lot::Mutex<Vec<f32>>> =
        Arc::new(parking_lot::Mutex::new(Vec::with_capacity(sample_rate as usize * 30)));

    let stream = match fmt {
        cpal::SampleFormat::F32 => {
            let b = Arc::clone(&buf);
            device.build_input_stream(
                &stream_cfg,
                move |data: &[f32], _| b.lock().extend_from_slice(data),
                |e| log::error!("Audio stream error: {e}"),
                None,
            )?
        }
        cpal::SampleFormat::I16 => {
            let b = Arc::clone(&buf);
            device.build_input_stream(
                &stream_cfg,
                move |data: &[i16], _| {
                    b.lock().extend(data.iter().map(|&s| s as f32 / i16::MAX as f32))
                },
                |e| log::error!("Audio stream error: {e}"),
                None,
            )?
        }
        cpal::SampleFormat::U16 => {
            let b = Arc::clone(&buf);
            device.build_input_stream(
                &stream_cfg,
                move |data: &[u16], _| {
                    b.lock().extend(
                        data.iter()
                            .map(|&s| s as f32 / u16::MAX as f32 * 2.0 - 1.0),
                    )
                },
                |e| log::error!("Audio stream error: {e}"),
                None,
            )?
        }
        other => return Err(anyhow!("Unsupported sample format: {other:?}")),
    };

    stream.play()?;
    log::debug!("Recording started ({sample_rate} Hz, {channels}ch, {fmt:?})");

    // Spin until the stop flag is set (key release).
    while !stop.load(Ordering::Relaxed) {
        std::thread::sleep(std::time::Duration::from_millis(10));
    }

    drop(stream); // stops the cpal callback
    let samples = buf.lock().clone();
    log::debug!("Recording stopped: {} samples captured", samples.len());

    Ok((samples, sample_rate, channels))
}
