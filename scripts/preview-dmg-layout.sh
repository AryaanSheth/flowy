#!/usr/bin/env zsh
set -euo pipefail

APP_NAME="Flowy"
REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
PREVIEW_DIR="${1:-/private/tmp/flowy-dmg-preview}"
BACKGROUND_DIR="$PREVIEW_DIR/.background"
BACKGROUND="$BACKGROUND_DIR/background.png"
MODULE_CACHE="$REPO_ROOT/.build/module-cache"
RELEASE_APP="$REPO_ROOT/target/release/bundle/macos/$APP_NAME.app"
DEBUG_APP="$REPO_ROOT/target/debug/bundle/macos/$APP_NAME.app"

rm -rf "$PREVIEW_DIR"
mkdir -p "$BACKGROUND_DIR" "$MODULE_CACHE"

if [[ -d "$RELEASE_APP" ]]; then
  cp -R "$RELEASE_APP" "$PREVIEW_DIR/$APP_NAME.app"
elif [[ -d "$DEBUG_APP" ]]; then
  cp -R "$DEBUG_APP" "$PREVIEW_DIR/$APP_NAME.app"
else
  mkdir -p "$PREVIEW_DIR/$APP_NAME.app/Contents/Resources"
  if [[ -f "$REPO_ROOT/icons/icon.icns" ]]; then
    cp "$REPO_ROOT/icons/icon.icns" "$PREVIEW_DIR/$APP_NAME.app/Contents/Resources/icon.icns"
  fi
  cat > "$PREVIEW_DIR/$APP_NAME.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.flowy.preview</string>
  <key>CFBundleIconFile</key>
  <string>icon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
EOF
fi

ln -s /Applications "$PREVIEW_DIR/Applications"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  xcrun swift "$REPO_ROOT/scripts/dmg-background.swift" "$BACKGROUND"

osascript <<EOF >/dev/null
tell application "Finder"
  set previewFolder to POSIX file "$PREVIEW_DIR" as alias
  open previewFolder
  activate
  delay 0.2

  set previewWindow to front window
  set current view of previewWindow to icon view
  set toolbar visible of previewWindow to false
  set statusbar visible of previewWindow to false
  set bounds of previewWindow to {100, 100, 760, 520}

  set viewOptions to icon view options of previewWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 104
  set text size of viewOptions to 14
  set background picture of viewOptions to POSIX file "$BACKGROUND"

  set position of item "$APP_NAME.app" of previewWindow to {190, 230}
  set position of item "Applications" of previewWindow to {490, 230}
end tell
EOF

echo "Preview opened: $PREVIEW_DIR"
echo "Run again after editing scripts/dmg-background.swift to refresh the view."
