#!/usr/bin/env zsh
set -euo pipefail

APP_NAME="Flowy"
VERSION="${1:-0.2.0}"

REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
APP_BUNDLE="$REPO_ROOT/target/release/bundle/macos/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_OUT="$REPO_ROOT/target/release/$DMG_NAME"
RW_DMG="$REPO_ROOT/target/release/$APP_NAME-$VERSION-rw.dmg"
STAGING="$(mktemp -d)"
BACKGROUND_DIR="$STAGING/.background"
BACKGROUND="$BACKGROUND_DIR/background.png"
MODULE_CACHE="$REPO_ROOT/.build/module-cache"

hdiutil_retry() {
  local attempts=4
  local delay=2
  local output
  local status_code

  for attempt in $(seq 1 "$attempts"); do
    set +e
    output="$(hdiutil "$@" 2>&1)"
    status_code=$?
    set -e

    if [[ "$status_code" -eq 0 ]]; then
      printf '%s\n' "$output"
      return 0
    fi

    if [[ "$attempt" -eq "$attempts" || "$output" != *"Resource busy"* ]]; then
      printf '%s\n' "$output" >&2
      return "$status_code"
    fi

    printf 'hdiutil %s failed with Resource busy; retrying (%d/%d)...\n' "$1" "$attempt" "$attempts" >&2
    sleep "$delay"
  done
}

cleanup() {
  [[ -n "${MOUNT_POINT:-}" ]] && hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  rm -rf "$STAGING"
  rm -f "$RW_DMG"
}
trap cleanup EXIT

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  echo "Run 'make build' first." >&2
  exit 1
fi

echo "Staging: $STAGING"
mkdir -p "$BACKGROUND_DIR" "$MODULE_CACHE"
cp -R "$APP_BUNDLE" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  xcrun swift "$REPO_ROOT/scripts/dmg-background.swift" "$BACKGROUND"

echo "Creating $DMG_NAME..."
hdiutil_retry create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -ov \
  -format UDRW \
  "$RW_DMG"

MOUNT_OUTPUT="$(hdiutil_retry attach "$RW_DMG" -readwrite -noverify -noautoopen)"
MOUNT_POINT="$(printf '%s\n' "$MOUNT_OUTPUT" | awk '/\/Volumes\// {print substr($0, index($0, "/Volumes/")); exit}')"

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
  echo "Could not mount DMG for layout" >&2
  printf '%s\n' "$MOUNT_OUTPUT" >&2
  exit 1
fi

osascript <<EOF >/dev/null
tell application "Finder"
  set dmgFolder to POSIX file "$MOUNT_POINT" as alias
  set backgroundFile to POSIX file "$MOUNT_POINT/.background/background.png" as alias
  open dmgFolder
  activate
  delay 0.5

  set dmgWindow to front window
  set current view of dmgWindow to icon view
  set toolbar visible of dmgWindow to false
  set statusbar visible of dmgWindow to false
  set bounds of dmgWindow to {100, 100, 760, 520}

  set viewOptions to icon view options of dmgWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 104
  set text size of viewOptions to 14
  set background picture of viewOptions to backgroundFile

  set position of item "$APP_NAME.app" of dmgWindow to {190, 230}
  set position of item "Applications" of dmgWindow to {490, 230}
  close dmgWindow
end tell
EOF

sync
hdiutil_retry detach "$MOUNT_POINT"
MOUNT_POINT=""

hdiutil_retry convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$DMG_OUT"
echo "Done: $DMG_OUT"

# Unversioned alias so releases/latest/download/Flowy.dmg always resolves
cp "$DMG_OUT" "$REPO_ROOT/target/release/Flowy.dmg"
echo "Alias: $REPO_ROOT/target/release/Flowy.dmg"
