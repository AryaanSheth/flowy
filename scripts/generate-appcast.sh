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
          <p>A small cleanup release for the updater itself.</p>
          <ul>
            <li><strong>Cleaner update notes:</strong> Sparkle now renders this compact changelog directly instead of embedding GitHub.</li>
            <li><strong>Reliable update checks:</strong> Keeps the corrected numeric Sparkle versioning path.</li>
            <li><strong>Website refresh:</strong> Latest download and release notes now point at $VERSION.</li>
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
