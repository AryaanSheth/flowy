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
      <p class="lead">$APP_NAME $VERSION adds the v1 foundations: safer app rules, language selection, toggle dictation, schema migrations, and test coverage.</p>
      <ul>
        <li>Adds a language picker so dictation no longer depends only on the system locale.</li>
        <li>Adds hold or toggle hotkey modes for short commands and long-form dictation.</li>
        <li>Adds per-app safety rules, including disabled apps, clipboard-only apps, and secure-field avoidance.</li>
        <li>Adds schema-versioned config migration plus focused logic tests for the risky text-rewrite paths.</li>
      </ul>
      <p class="foot">Local speech-to-text for macOS. No telemetry. No account. No subscription.</p>
    </section>
  </main>
</body>
</html>
EOF

echo "Generated release notes: $OUT"
