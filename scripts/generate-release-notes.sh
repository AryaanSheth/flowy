#!/usr/bin/env zsh
set -euo pipefail

APP_NAME="Flowy"

usage() {
  cat <<EOF
Usage: scripts/generate-release-notes.sh <version> [output-path]

Generates the small HTML page Sparkle renders inside its update window.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 2
fi

VERSION="$1"
OUT="${2:-target/release/release-notes.html}"

case "$VERSION" in
  1.1.2)
    LEAD="$APP_NAME $VERSION captures the last words you speak before stopping."
    ITEMS='
        <li>Fixes the final ~1 second of speech being dropped when you stop dictation immediately after talking. Flowy now waits for the recognizer to flush its buffer instead of cutting off early.</li>'
    ;;
  1.1.1)
    LEAD="$APP_NAME $VERSION makes local AI polish faster and smarter."
    ITEMS='
        <li>Warms up Ollama when recording starts so model load happens while you speak instead of after release.</li>
        <li>Switches the default recommended local polish model to Gemma 3 1B for lower latency.</li>
        <li>Adds Smart Polish prompting that infers intent, repairs unclear fragments, and uses bullets or numbered lists when the dictated structure calls for it.</li>
        <li>Keeps local model polish bounded with short timeouts, compact prompts, and capped response tokens.</li>'
    ;;
  1.1.0)
    LEAD="$APP_NAME $VERSION adds optional live streaming and first-class local AI polish with Ollama."
    ITEMS='
        <li>Makes live text streaming optional and off by default for safer final-text delivery.</li>
        <li>Adds a dedicated AI settings tab for local Ollama polish, model selection, tone presets, and recommended model pulls.</li>
        <li>Keeps transcripts local: Apple Speech handles dictation and Ollama polish runs only against the configured local endpoint.</li>
        <li>Fixes settings persistence so output mode is no longer silently reset while saving other preferences.</li>'
    ;;
  1.0.0)
    LEAD="$APP_NAME $VERSION is the first stable release, with hardened release automation and safer dictation delivery paths."
    ITEMS='
        <li>Fixes release version propagation so the app bundle, DMG, GitHub release, and Sparkle metadata agree.</li>
        <li>Adds CI coverage for macOS app builds, Swift tests, release-candidate DMG packaging, and mounted DMG contents.</li>
        <li>Keeps the streaming duplicate fix, append-only reset protection, and inject-only clipboard preservation in the stable release.</li>
        <li>Confirms unsigned install expectations: right-click Open on first launch, then guided permissions for Microphone, Speech Recognition, and Accessibility.</li>'
    ;;
  0.8.1)
    LEAD="$APP_NAME $VERSION fixes a live dictation duplication bug and tightens the active recording overlay."
    ITEMS='
        <li>Fixes reset-like speech partials being appended repeatedly during longer dictation sessions.</li>
        <li>Keeps live streaming append-only protection, but now requires reliable word overlap before adding continuation text.</li>
        <li>Adds regression coverage for duplicate reset partials and valid reset continuations.</li>
        <li>Shrinks the active dictation wave pill so it stays lighter at the top of the screen.</li>'
    ;;
  0.8.0)
    LEAD="$APP_NAME $VERSION adds the v1 foundations: safer app rules, language selection, toggle dictation, schema migrations, and test coverage."
    ITEMS='
        <li>Adds a language picker so dictation no longer depends only on the system locale.</li>
        <li>Adds hold or toggle hotkey modes for short commands and long-form dictation.</li>
        <li>Adds per-app safety rules, including disabled apps, clipboard-only apps, and secure-field avoidance.</li>
        <li>Adds schema-versioned config migration plus focused logic tests for the risky text-rewrite paths.</li>'
    ;;
  *)
    LEAD="$APP_NAME $VERSION includes the latest Flowy fixes and refinements."
    ITEMS='
        <li>Includes the newest app fixes, UI refinements, and reliability improvements.</li>
        <li>Keeps Flowy local, lightweight, and focused on fast macOS dictation.</li>'
    ;;
esac

mkdir -p "$(dirname "$OUT")"

cat > "$OUT" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$APP_NAME $VERSION Release Notes</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0b1014;
      --panel: #10181d;
      --ink: #f3f7f6;
      --muted: #aeb9b6;
      --line: rgba(115, 235, 218, 0.18);
      --accent: #57d9cf;
      --accent-2: #d7fff8;
    }

    * { box-sizing: border-box; }

    html, body {
      margin: 0;
      min-height: 100%;
      background:
        radial-gradient(circle at 16% 8%, rgba(87, 217, 207, 0.12), transparent 34%),
        linear-gradient(145deg, #0b1014 0%, #101417 100%);
      color: var(--ink);
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
      line-height: 1.45;
      -webkit-font-smoothing: antialiased;
    }

    body { padding: 28px; }

    .wrap {
      max-width: 680px;
      margin: 0 auto;
      border: 1px solid var(--line);
      border-radius: 22px;
      background: rgba(16, 24, 29, 0.76);
      box-shadow: 0 18px 60px rgba(0, 0, 0, 0.28);
      overflow: hidden;
    }

    .top {
      display: flex;
      align-items: center;
      gap: 14px;
      padding: 22px 24px 18px;
      border-bottom: 1px solid var(--line);
    }

    .mark {
      width: 58px;
      height: 58px;
      border-radius: 18px;
      display: grid;
      place-items: center;
      color: white;
      font-weight: 800;
      letter-spacing: -0.04em;
      background: linear-gradient(145deg, #bfc2c0, #8d918f);
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.28);
      flex: 0 0 auto;
    }

    .wave {
      color: var(--accent);
      font-size: 24px;
      font-weight: 750;
      letter-spacing: -0.04em;
    }

    .eyebrow {
      margin: 0 0 2px;
      color: var(--accent);
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.14em;
      text-transform: uppercase;
    }

    h1 {
      margin: 0;
      color: var(--ink);
      font-size: 28px;
      line-height: 1.05;
      letter-spacing: -0.03em;
    }

    .body { padding: 24px; }

    .lead {
      margin: 0 0 20px;
      color: var(--muted);
      font-size: 16px;
      max-width: 54ch;
    }

    ul {
      display: grid;
      gap: 12px;
      list-style: none;
      margin: 0;
      padding: 0;
    }

    li {
      position: relative;
      padding: 14px 16px 14px 42px;
      border: 1px solid rgba(255, 255, 255, 0.07);
      border-radius: 14px;
      background: rgba(255, 255, 255, 0.035);
      color: var(--accent-2);
      font-size: 15px;
    }

    li::before {
      content: "";
      position: absolute;
      left: 16px;
      top: 19px;
      width: 10px;
      height: 10px;
      border-radius: 999px;
      background: var(--accent);
      box-shadow: 0 0 18px rgba(87, 217, 207, 0.55);
    }

    .foot {
      margin-top: 20px;
      color: #7f8c89;
      font-size: 12px;
    }
  </style>
</head>
<body>
  <main class="wrap">
    <header class="top">
      <div class="mark" aria-hidden="true"><span class="wave">~</span>flowy</div>
      <div>
        <p class="eyebrow">Update available</p>
        <h1>$APP_NAME $VERSION</h1>
      </div>
    </header>

    <section class="body" aria-label="Release notes">
      <p class="lead">$LEAD</p>
      <ul>
$ITEMS
      </ul>
      <p class="foot">Local speech-to-text for macOS. No telemetry. No account. No subscription.</p>
    </section>
  </main>
</body>
</html>
EOF

echo "Generated release notes: $OUT"
