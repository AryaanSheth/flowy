#!/usr/bin/env zsh
set -euo pipefail

APP_NAME="Flowy"
BUNDLE_ID="com.flowy.app"
VERSION="0.8.1"
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

REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
CONFIGURATION="release"
CHECK_ONLY=0
CLEAN=0

usage() {
  cat <<EOF
Usage: scripts/build-macos.sh [--debug] [--release] [--check-only] [--clean]

Build the native macOS-only Flowy app bundle.

Options:
  --debug       Compile with debug settings into target/debug.
  --release     Compile with release settings into target/release. Default.
  --check-only  Build the bundle but do not print launch instructions.
  --clean       Remove this configuration's native build output first.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      CONFIGURATION="debug"
      ;;
    --release)
      CONFIGURATION="release"
      ;;
    --check-only)
      CHECK_ONLY=1
      ;;
    --clean)
      CLEAN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

cd "$REPO_ROOT"

"$REPO_ROOT/scripts/doctor-swift.sh" --quiet

BUILD_ROOT="$REPO_ROOT/.build/flowy-native/$CONFIGURATION"
TARGET_ROOT="$REPO_ROOT/target/$CONFIGURATION"
APP_BUNDLE="$TARGET_ROOT/bundle/macos/$APP_NAME.app"
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
RESOURCES="$APP_BUNDLE/Contents/Resources"
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
MODULE_CACHE="$REPO_ROOT/.build/module-cache"
SPARKLE_FRAMEWORK_PATH="${FLOWY_SPARKLE_FRAMEWORK_PATH:-$REPO_ROOT/vendor/Sparkle/Sparkle.framework}"
SPARKLE_PUBLIC_ED_KEY="${FLOWY_SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_FEED_URL="${FLOWY_SPARKLE_FEED_URL:-https://github.com/AryaanSheth/flowy/releases/latest/download/appcast.xml}"
BUNDLE_VERSION="$(sparkle_build_version "$VERSION")"

if [[ "$CLEAN" -eq 1 ]]; then
  rm -rf "$BUILD_ROOT" "$APP_BUNDLE"
fi

mkdir -p "$BUILD_ROOT" "$APP_BUNDLE/Contents/MacOS" "$RESOURCES" "$MODULE_CACHE"

SWIFT_FLAGS=(
  -target "arm64-apple-macos$MIN_MACOS"
  -module-cache-path "$MODULE_CACHE"
  -parse-as-library
)

if [[ "$CONFIGURATION" == "release" ]]; then
  SWIFT_FLAGS+=(-O -whole-module-optimization)
else
  SWIFT_FLAGS+=(-Onone -g)
fi

FRAMEWORKS=(
  -framework AppKit
  -framework ApplicationServices
  -framework AudioToolbox
  -framework AVFoundation
  -framework Carbon
  -framework ServiceManagement
  -framework Speech
  -framework SwiftUI
  -Xlinker -weak_framework -Xlinker Translation
)

SPARKLE_PLIST=""
if [[ -d "$SPARKLE_FRAMEWORK_PATH" ]]; then
  SPARKLE_PARENT="$(dirname "$SPARKLE_FRAMEWORK_PATH")"
  SWIFT_FLAGS+=(-F "$SPARKLE_PARENT")
  FRAMEWORKS+=(
    -F "$SPARKLE_PARENT"
    -framework Sparkle
    -Xlinker -rpath -Xlinker "@executable_path/../Frameworks"
  )

  mkdir -p "$FRAMEWORKS_DIR"
  rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
  cp -R "$SPARKLE_FRAMEWORK_PATH" "$FRAMEWORKS_DIR/Sparkle.framework"
  echo "Bundling Sparkle.framework"

  if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    SPARKLE_PLIST="  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_ED_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <false/>"
  else
    echo "FLOWY_SPARKLE_PUBLIC_ED_KEY is not set; Sparkle will be bundled but disabled at runtime"
  fi
fi

echo "Building $APP_NAME ($CONFIGURATION, arm64 macOS $MIN_MACOS+)..."
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
xcrun swiftc "${SWIFT_FLAGS[@]}" Sources/Flowy/*.swift "${FRAMEWORKS[@]}" -o "$EXECUTABLE"

if [[ -f "$REPO_ROOT/icons/icon.icns" ]]; then
  cp "$REPO_ROOT/icons/icon.icns" "$RESOURCES/icon.icns"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>icon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUNDLE_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Flowy needs microphone access to record your voice for transcription.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Flowy uses speech recognition to convert your voice to text.</string>
  <key>NSSupportsAutomaticTermination</key>
  <false/>
  <key>NSSupportsSuddenTermination</key>
  <false/>
$SPARKLE_PLIST
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
  CODESIGN_IDENTITY="${FLOWY_CODESIGN_IDENTITY:--}"
  codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE" >/dev/null
fi

echo "Built: $APP_BUNDLE"
/usr/bin/file "$EXECUTABLE"

if [[ "$CHECK_ONLY" -eq 0 ]]; then
  echo
  echo "Launch with:"
  echo "  open \"$APP_BUNDLE\""
fi
