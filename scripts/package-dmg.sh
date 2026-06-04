#!/usr/bin/env zsh
set -euo pipefail

APP_NAME="Flowy"
VERSION="${1:-0.5.1}"

REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
APP_BUNDLE="$REPO_ROOT/target/release/bundle/macos/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_OUT="$REPO_ROOT/target/release/$DMG_NAME"
RW_DMG="$REPO_ROOT/target/release/$APP_NAME-$VERSION-rw.dmg"
STAGING="$(mktemp -d)"
MODULE_CACHE="$REPO_ROOT/.build/module-cache"
MOUNT_DIR=""

cleanup() {
  set +e
  if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || hdiutil detach "$MOUNT_DIR" -force -quiet >/dev/null 2>&1
  fi
  rm -rf "$STAGING" "$RW_DMG"
}
trap cleanup EXIT

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  echo "Run 'make build' first." >&2
  exit 1
fi

echo "Staging: $STAGING"
mkdir -p "$STAGING/.background"
mkdir -p "$MODULE_CACHE"
cp -R "$APP_BUNDLE" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" xcrun swift "$REPO_ROOT/scripts/dmg-background.swift" "$STAGING/.background/background.png"

echo "Creating $DMG_NAME..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDRW \
  -fs HFS+ \
  "$RW_DMG"

MOUNT_DIR="$(
  hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen \
    | awk '/\/Volumes\// { print substr($0, index($0, "/Volumes/")); exit }'
)"

if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
  echo "Could not mount $RW_DMG" >&2
  exit 1
fi

echo "Applying Finder layout..."
osascript <<EOF >/dev/null
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 760, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 104
    set text size of viewOptions to 14
    set background picture of viewOptions to POSIX file "$MOUNT_DIR/.background/background.png"
    set position of item "$APP_NAME.app" of container window to {190, 230}
    set position of item "Applications" of container window to {490, 230}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF

bless --folder "$MOUNT_DIR" --openfolder "$MOUNT_DIR" >/dev/null 2>&1 || true
sync
hdiutil detach "$MOUNT_DIR" -quiet
MOUNT_DIR=""

hdiutil convert "$RW_DMG" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_OUT"

echo "Done: $DMG_OUT"

# Unversioned alias so releases/latest/download/Flowy.dmg always resolves
cp "$DMG_OUT" "$REPO_ROOT/target/release/Flowy.dmg"
echo "Alias: $REPO_ROOT/target/release/Flowy.dmg"
