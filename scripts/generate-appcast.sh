#!/usr/bin/env zsh
set -euo pipefail

APP_NAME="Flowy"
MIN_MACOS="13.0"

sparkle_build_version() {
  local version="$1"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$version"
  major="${major:-0}"
  minor="${minor:-0}"
  patch="${patch:-0}"
  printf '%d' "$((10#$major * 10000 + 10#$minor * 100 + 10#$patch))"
}

usage() {
  cat <<EOF
Usage: scripts/generate-appcast.sh <version> <dmg-path> [output-path]

Requires FLOWY_SPARKLE_PRIVATE_ED_KEY to sign the DMG enclosure.
EOF
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage >&2
  exit 2
fi

VERSION="$1"
DMG_PATH="$2"
OUT="${3:-target/release/appcast.xml}"
BUILD_VERSION="$(sparkle_build_version "$VERSION")"

REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
SIGN_UPDATE="${FLOWY_SPARKLE_SIGN_UPDATE:-$REPO_ROOT/vendor/Sparkle/bin/sign_update}"
PRIVATE_KEY="${FLOWY_SPARKLE_PRIVATE_ED_KEY:-}"
RELEASE_BASE_URL="${FLOWY_RELEASE_BASE_URL:-https://github.com/AryaanSheth/flowy/releases/download/v$VERSION}"
DMG_NAME="$(basename "$DMG_PATH")"
DMG_URL="$RELEASE_BASE_URL/$DMG_NAME"
RELEASE_URL="https://github.com/AryaanSheth/flowy/releases/tag/v$VERSION"
case "$VERSION" in
  1.2.1)
    NOTES_LEAD="v1.2.1 adds an optional local Whisper engine for higher accuracy."
    NOTES_ITEMS='
            <li><strong>Local Whisper engine:</strong> Choose Whisper (local) under Settings &rsaquo; Engine for more accurate on-device transcription. The base model (~150 MB) downloads on first use.</li>
            <li><strong>Apple still default:</strong> The Apple on-device engine remains the default and keeps live streaming, live WPM, and auto-stop on silence.</li>
            <li><strong>Sharper recognition:</strong> Custom dictionary words now bias the recognizer up front, and history persists across launches.</li>'
    ;;
  1.1.2)
    NOTES_LEAD="v1.1.2 captures the last words you speak before stopping."
    NOTES_ITEMS='
            <li><strong>No more dropped tail:</strong> Stopping dictation right after you finish talking no longer loses the final ~1 second of speech. Flowy now waits for the recognizer to flush its buffer instead of cutting off early.</li>'
    ;;
  1.1.1)
    NOTES_LEAD="v1.1.1 makes local AI polish faster and smarter."
    NOTES_ITEMS='
            <li><strong>Faster AI polish:</strong> Ollama now warms up when recording starts, so model load can happen while you speak instead of after release.</li>
            <li><strong>Fast default model:</strong> New and default-model installs use Gemma 3 1B for lower-latency local polish.</li>
            <li><strong>Smart Polish:</strong> The default polish prompt now infers intent, fixes unclear fragments, and formats spoken lists as bullets or numbered steps when appropriate.</li>
            <li><strong>Latency guardrails:</strong> Local model polish uses compact prompts, capped response tokens, and short timeouts so dictation falls back quickly if Ollama is slow.</li>'
    ;;
  1.1.0)
    NOTES_LEAD="v1.1.0 adds optional live streaming and first-class local AI polish with Ollama."
    NOTES_ITEMS='
            <li><strong>Safer streaming:</strong> Live partial insertion is now optional and off by default, while final text delivery remains the safe default.</li>
            <li><strong>Local AI polish:</strong> Adds a dedicated AI tab for Ollama status, endpoint, model selection, tone presets, custom prompts, and recommended model pulls.</li>
            <li><strong>Local-first:</strong> Apple Speech still performs dictation locally, and model polish uses only the configured local Ollama endpoint.</li>
            <li><strong>Settings fix:</strong> Saving preferences no longer silently resets output mode.</li>'
    ;;
  1.0.0)
    NOTES_LEAD="v1.0.0 is Flowy's first stable release, focused on reliable local dictation and a hardened unsigned release path."
    NOTES_ITEMS='
            <li><strong>Release confidence:</strong> The app bundle, DMG, GitHub release, and Sparkle appcast now use the same tag-derived version.</li>
            <li><strong>CI coverage:</strong> macOS CI builds the app, runs Swift tests, packages a release-candidate DMG, and verifies mounted DMG contents.</li>
            <li><strong>Dictation stability:</strong> Includes the streaming duplicate fix, append-only reset protection, and inject-only clipboard preservation.</li>
            <li><strong>Unsigned install clarity:</strong> Keeps the right-click Open first-launch path and guided permission recovery for Microphone, Speech Recognition, and Accessibility.</li>'
    ;;
  0.8.1)
    NOTES_LEAD="v0.8.1 fixes live dictation duplication and makes the active recording overlay smaller."
    NOTES_ITEMS='
            <li><strong>Streaming fix:</strong> Reset-like speech partials no longer get appended repeatedly during long dictation sessions.</li>
            <li><strong>Safer continuation:</strong> Live insertion now requires reliable word overlap before appending reset continuation text.</li>
            <li><strong>Regression coverage:</strong> Adds focused tests for duplicate reset partials and valid reset continuations.</li>
            <li><strong>Smaller overlay:</strong> The active dictation wave pill is about half its previous size.</li>'
    ;;
  0.8.0)
    NOTES_LEAD="v0.8 adds the foundations Flowy needs before a stable v1."
    NOTES_ITEMS='
            <li><strong>Language picker:</strong> Choose a dictation locale instead of relying only on the system locale.</li>
            <li><strong>Toggle dictation:</strong> Use the hotkey as hold-to-talk or tap-to-start/tap-to-stop.</li>
            <li><strong>Per-app safety:</strong> Disable Flowy or force clipboard-only behavior for specific apps, with secure-field avoidance.</li>
            <li><strong>v1 groundwork:</strong> Schema-versioned config migration, experimental AI gating, and focused logic tests.</li>'
    ;;
  *)
    NOTES_LEAD="v$VERSION includes the latest Flowy fixes and refinements."
    NOTES_ITEMS='
            <li><strong>Latest fixes:</strong> Includes the newest app fixes, UI refinements, and reliability improvements.</li>
            <li><strong>Local dictation:</strong> Keeps Flowy local, lightweight, and focused on fast macOS speech-to-text.</li>'
    ;;
esac
if [[ -z "$PRIVATE_KEY" ]]; then
  echo "FLOWY_SPARKLE_PRIVATE_ED_KEY is required to generate a signed Sparkle appcast" >&2
  exit 1
fi

if [[ ! -x "$SIGN_UPDATE" ]]; then
  echo "Sparkle sign_update tool not found: $SIGN_UPDATE" >&2
  echo "Run scripts/install-sparkle.sh first." >&2
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
SIGNATURE_ATTRS="$(printf '%s' "$PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$DMG_PATH" | tr -d '\n')"
PUB_DATE="$(LC_ALL=C TZ=UTC date '+%a, %d %b %Y %H:%M:%S +0000')"

cat > "$OUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$APP_NAME Updates</title>
    <description>Latest $APP_NAME releases</description>
    <language>en</language>
    <item>
      <title>$APP_NAME $VERSION</title>
      <link>$RELEASE_URL</link>
      <sparkle:version>$BUILD_VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <description>
        <![CDATA[
          <style>
            body { font: -apple-system-body; }
            h3 { margin: 0 0 0.65em; font: -apple-system-headline; }
            p { margin: 0 0 0.8em; color: #d7dddc; }
            ul { margin: 0; padding-left: 1.2em; }
            li { margin: 0 0 0.45em; }
            strong { color: #57d9cf; font-weight: 700; }
          </style>
          <h3>Flowy $VERSION</h3>
          <p>$NOTES_LEAD</p>
          <ul>
$NOTES_ITEMS
          </ul>
        ]]>
      </description>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure url="$DMG_URL" $SIGNATURE_ATTRS type="application/x-apple-diskimage" />
      <sparkle:minimumSystemVersion>$MIN_MACOS</sparkle:minimumSystemVersion>
    </item>
  </channel>
</rss>
EOF

echo "Generated Sparkle appcast: $OUT"
