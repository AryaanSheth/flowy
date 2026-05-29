#!/usr/bin/env zsh
set -euo pipefail

APP_NAME="Flowy"
VERSION="${1:-0.1.0}"

REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
APP_BUNDLE="$REPO_ROOT/target/release/bundle/macos/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_OUT="$REPO_ROOT/target/release/$DMG_NAME"
STAGING="$(mktemp -d)"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  echo "Run 'make build' first." >&2
  exit 1
fi

echo "Staging: $STAGING"
cp -R "$APP_BUNDLE" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

echo "Creating $DMG_NAME..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_OUT"

rm -rf "$STAGING"
echo "Done: $DMG_OUT"
