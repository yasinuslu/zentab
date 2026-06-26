#!/usr/bin/env bash
# Shared helpers for ZenTab's bin/ scripts. Source this — don't run it directly.
set -euo pipefail

# Always operate from the repo root, wherever the script was invoked from.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Some shells (e.g. a Nix/home-manager profile) export LD=ld / LINKER, which
# xcodebuild wrongly uses as the linker — clang-driver flags then get passed to
# ld and the link step fails. Xcode.app is unaffected; CLI builds are not.
# Clear them here so bin/* works from any terminal. (Local-only; does not touch
# your interactive shell.)
unset LD LINKER 2>/dev/null || true

PROJECT="ZenTab.xcodeproj"
SCHEME="ZenTab"
DESTINATION="platform=macOS"

# Run xcodebuild, prettifying its output when xcbeautify is installed
# (`brew bundle`). Exit status is preserved either way.
xcb() {
  if command -v xcbeautify >/dev/null 2>&1; then
    set -o pipefail
    xcodebuild "$@" | xcbeautify
  else
    xcodebuild "$@"
  fi
}
