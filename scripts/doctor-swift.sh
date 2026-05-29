#!/usr/bin/env zsh
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
QUIET=0

if [[ "${1:-}" == "--quiet" ]]; then
  QUIET=1
fi

MODULE_CACHE="$REPO_ROOT/.build/module-cache"
mkdir -p "$MODULE_CACHE"

if [[ "$QUIET" -eq 0 ]]; then
  echo "Swift:"
  swift --version || true
  echo
  echo "Developer directory:"
  xcode-select -p || true
  echo
  echo "SDK:"
  xcrun --show-sdk-path || true
  echo
  echo "Checking Foundation import..."
fi

set +e
OUTPUT="$(
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  swift -module-cache-path "$MODULE_CACHE" -e 'import Foundation; print("ok")' 2>&1
)"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  [[ "$QUIET" -eq 1 ]] || echo "$OUTPUT"
  exit 0
fi

cat >&2 <<EOF
Swift toolchain check failed.

This means the active Swift compiler cannot import Apple's Foundation module.
Flowy cannot be compiled until Command Line Tools or Xcode are repaired.

Current toolchain:
$(swift --version 2>&1 || true)

Developer directory:
$(xcode-select -p 2>&1 || true)

SDK:
$(xcrun --show-sdk-path 2>&1 || true)

Compiler error:
$OUTPUT

Recommended fix:
  sudo rm -rf /Library/Developer/CommandLineTools
  xcode-select --install

Then open a new terminal and run:
  cd "$REPO_ROOT"
  make doctor
  make build
EOF

exit "$STATUS"
