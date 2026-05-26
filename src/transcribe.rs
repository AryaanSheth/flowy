use anyhow::{anyhow, Result};
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

/// Owns a loaded Whisper model.
///
/// `WhisperContext` is safe to share between threads (the crate implements
/// `Send + Sync` via an unsafe impl on its internal raw pointer, which is
/// valid because the context is read-only after construction).
pub struct Transcriber {
    ctx: WhisperContext,
}

impl Transcriber {
    /// Load a ggml model file from disk.  Blocks while the model is mmap'd
    /// and validated; typically < 1 s for tiny/base models.
    pub fn load(model_path: &str) -> Result<Self> {
        log::info!("Loading Whisper model from: {model_path}");
        let ctx = WhisperContext::new_with_params(model_path, WhisperContextParameters::default())
            .map_err(|e| anyhow!("Failed to load model '{model_path}': {e:?}"))?;
        log::info!("Model loaded successfully");
        Ok(Self { ctx })
    }

    /// Run inference on 16 kHz mono f32 samples.
    ///
    /// `language` should be an ISO 639-1 code ("en", "fr", …) or `"auto"` for
    /// automatic language detection.
    pub fn transcribe(&self, samples: &[f32], language: &str) -> Result<String> {
        let mut state = self
            .ctx
            .create_state()
            .map_err(|e| anyhow!("Could not create Whisper state: {e:?}"))?;

        let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });

        let lang_opt = (language != "auto").then_some(language);
        params.set_language(lang_opt);
        params.set_print_special(false);
        params.set_print_progress(false);
        params.set_print_realtime(false);
        params.set_print_timestamps(false);
        // Single-utterance mode — better latency for short recordings.
        params.set_no_context(true);
        params.set_single_segment(false);

        state
            .full(params, samples)
            .map_err(|e| anyhow!("Whisper inference failed: {e:?}"))?;

        let n = state
            .full_n_segments()
            .map_err(|e| anyhow!("Could not get segment count: {e:?}"))?;

        let mut text = String::new();
        for i in 0..n {
            let seg = state
                .full_get_segment_text(i)
                .map_err(|e| anyhow!("Could not read segment {i}: {e:?}"))?;
            let seg = seg.trim();
            if !seg.is_empty() {
                if !text.is_empty() {
                    text.push(' ');
                }
                text.push_str(seg);
            }
        }

        Ok(text)
    }
}
