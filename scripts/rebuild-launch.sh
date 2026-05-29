#!/usr/bin/env zsh
set -euo pipefail

APP_NAME="Flowy"
REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
TARGET_APP="$REPO_ROOT/target/release/bundle/macos/$APP_NAME.app"
INSTALLED_APP="/Applications/$APP_NAME.app"

CLEAN=1
INSTALL=0
RESET_ACCESSIBILITY=0

usage() {
  cat <<EOF
Usage: scripts/rebuild-launch.sh [--install] [--reset-accessibility] [--no-clean]

Build and launch a fresh native Flowy app bundle.

Options:
  --install    Copy the rebuilt app to /Applications and launch that copy.
  --reset-accessibility
               Reset Flowy's Accessibility permission before launching.
  --no-clean   Kept for compatibility; native builds are incremental by default.
  -h, --help   Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL=1
      ;;
    --reset-accessibility)
      RESET_ACCESSIBILITY=1
      ;;
    --no-clean)
      CLEAN=0
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

echo "Stopping existing Flowy instances..."
osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 1

if [[ "$CLEAN" -eq 1 ]]; then
  echo "Cleaning native release build artifacts..."
  rm -rf "$REPO_ROOT/target/release" "$REPO_ROOT/.build/flowy-native/release"
fi

echo "Building packaged app..."
"$REPO_ROOT/scripts/build-macos.sh"

APP_TO_OPEN="$TARGET_APP"
if [[ "$INSTALL" -eq 1 ]]; then
  echo "Installing rebuilt app to /Applications..."
  rm -rf "$INSTALLED_APP"
  cp -R "$TARGET_APP" /Applications/
  APP_TO_OPEN="$INSTALLED_APP"
fi

if [[ "$RESET_ACCESSIBILITY" -eq 1 ]]; then
  echo "Resetting Accessibility permission for com.flowy.app..."
  tccutil reset Accessibility com.flowy.app >/dev/null 2>&1 || true
fi

echo "Launching: $APP_TO_OPEN"
open -n "$APP_TO_OPEN"
sleep 2

if [[ "$RESET_ACCESSIBILITY" -eq 1 ]]; then
  echo "Opening Accessibility settings. Add or enable this app:"
  echo "  $APP_TO_OPEN"
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true
fi

echo
echo "Running Flowy process:"
if pids="$(pgrep -x "$APP_NAME")" && [[ -n "$pids" ]]; then
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    ps -p "$pid" -o pid=,command=
  done <<< "$pids"
else
  echo "No running $APP_NAME process found." >&2
  exit 1
fi

echo
echo "Expected bundle:"
echo "  $APP_TO_OPEN"
