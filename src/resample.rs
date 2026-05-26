use anyhow::Result;
use rubato::{
    Resampler, SincFixedIn, SincInterpolationParameters, SincInterpolationType, WindowFunction,
};

const TARGET_RATE: u32 = 16_000;
const CHUNK_SIZE:  usize = 1_024;

/// Downmixes multi-channel audio to mono and resamples to 16 kHz.
/// Returns a flat `Vec<f32>` ready for whisper-rs inference.
pub fn to_16khz_mono(samples: &[f32], from_rate: u32, channels: u16) -> Result<Vec<f32>> {
    // --- Downmix to mono ---
    let mono: Vec<f32> = if channels == 1 {
        samples.to_vec()
    } else {
        let n = channels as usize;
        samples
            .chunks(n)
            .map(|frame| frame.iter().sum::<f32>() / n as f32)
            .collect()
    };

    if from_rate == TARGET_RATE {
        return Ok(mono);
    }

    let ratio = TARGET_RATE as f64 / from_rate as f64;

    let params = SincInterpolationParameters {
        sinc_len: 128,
        f_cutoff: 0.95,
        interpolation: SincInterpolationType::Linear,
        oversampling_factor: 128,
        window: WindowFunction::BlackmanHarris2,
    };

    let mut resampler = SincFixedIn::<f32>::new(ratio, 2.0, params, CHUNK_SIZE, 1)?;

    // Pad to an exact multiple of CHUNK_SIZE so every call gets a full chunk.
    let padded_len = mono.len().div_ceil(CHUNK_SIZE) * CHUNK_SIZE;
    let mut padded = mono;
    padded.resize(padded_len, 0.0);

    let mut out = Vec::with_capacity((padded_len as f64 * ratio) as usize + 64);

    for chunk in padded.chunks(CHUNK_SIZE) {
        let waves_out = resampler.process(&[chunk.to_vec()], None)?;
        out.extend_from_slice(&waves_out[0]);
    }

    log::debug!(
        "Resampled {} → {} samples ({} Hz → {} Hz)",
        padded_len,
        out.len(),
        from_rate,
        TARGET_RATE
    );

    Ok(out)
}
