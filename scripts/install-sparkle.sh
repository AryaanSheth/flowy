#!/usr/bin/env zsh
set -euo pipefail

SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.3}"
SPARKLE_ARCHIVE="Sparkle-${SPARKLE_VERSION}.tar.xz"
SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/${SPARKLE_ARCHIVE}"

REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
VENDOR_DIR="$REPO_ROOT/vendor/Sparkle"
CACHE_DIR="$REPO_ROOT/.build/sparkle"
ARCHIVE_PATH="$CACHE_DIR/$SPARKLE_ARCHIVE"

mkdir -p "$CACHE_DIR"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "Downloading Sparkle $SPARKLE_VERSION..."
  curl -fL "$SPARKLE_URL" -o "$ARCHIVE_PATH"
fi

rm -rf "$VENDOR_DIR"
mkdir -p "$VENDOR_DIR"
tar -xf "$ARCHIVE_PATH" -C "$VENDOR_DIR"

if [[ ! -d "$VENDOR_DIR/Sparkle.framework" ]]; then
  echo "Sparkle.framework was not found after extraction" >&2
  exit 1
fi

echo "Installed Sparkle.framework to $VENDOR_DIR/Sparkle.framework"
echo "Sparkle tools are available in $VENDOR_DIR/bin"
