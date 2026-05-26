//! Optional post-processing of transcribed text through a local Ollama model.
//!
//! Whisper handles speech-to-text accurately but tends to drop punctuation,
//! capitalize inconsistently, and pass on filler words.  A small instruction-
//! tuned LLM like `llama3.2:3b` cleans this up in ~200 ms on Apple Silicon.
//!
//! All calls are synchronous (we're on a dedicated pipeline thread, not the
//! Tauri async runtime) and have explicit timeouts.

use std::time::Duration;

use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};

// ── Wire types ───────────────────────────────────────────────

#[derive(Serialize)]
struct GenRequest<'a> {
    model:   &'a str,
    prompt:  &'a str,
    system:  &'a str,
    stream:  bool,
    options: GenOptions,
}

#[derive(Serialize)]
struct GenOptions {
    temperature: f32,
}

#[derive(Deserialize)]
struct GenResponse {
    response: String,
}

#[derive(Deserialize)]
struct TagsResponse {
    models: Vec<TagModel>,
}

#[derive(Deserialize)]
struct TagModel {
    name: String,
}

// ── Public API ───────────────────────────────────────────────

/// Send `text` to Ollama for cleanup.
///
/// Returns the model's response trimmed of surrounding whitespace.  On any
/// error (Ollama not running, model not pulled, timeout) the caller should
/// fall back to the original text — that fallback is the responsibility of
/// the pipeline, not this function.
pub fn enhance(endpoint: &str, model: &str, system: &str, text: &str) -> Result<String> {
    if text.trim().is_empty() {
        return Ok(String::new());
    }

    let url = format!("{}/api/generate", endpoint.trim_end_matches('/'));
    let req = GenRequest {
        model,
        prompt:  text,
        system,
        stream:  false,
        options: GenOptions { temperature: 0.1 },
    };

    let body = serde_json::to_value(&req)
        .map_err(|e| anyhow!("Failed to serialise Ollama request: {e}"))?;

    let resp: GenResponse = ureq::post(&url)
        .timeout(Duration::from_secs(30))
        .send_json(body)
        .map_err(|e| anyhow!("Ollama request failed: {e}"))?
        .into_json()
        .map_err(|e| anyhow!("Ollama response was not valid JSON: {e}"))?;

    Ok(resp.response.trim().to_string())
}

/// List models currently installed in Ollama (`/api/tags`).
pub fn list_models(endpoint: &str) -> Result<Vec<String>> {
    let url = format!("{}/api/tags", endpoint.trim_end_matches('/'));
    let resp: TagsResponse = ureq::get(&url)
        .timeout(Duration::from_secs(3))
        .call()
        .map_err(|e| anyhow!("Could not reach Ollama at {url}: {e}"))?
        .into_json()
        .map_err(|e| anyhow!("Ollama /api/tags returned bad JSON: {e}"))?;

    Ok(resp.models.into_iter().map(|m| m.name).collect())
}

/// Best-effort liveness check used by the settings UI.
pub fn ping(endpoint: &str) -> bool {
    let url = format!("{}/api/tags", endpoint.trim_end_matches('/'));
    ureq::get(&url)
        .timeout(Duration::from_secs(2))
        .call()
        .map(|r| r.status() == 200)
        .unwrap_or(false)
}
