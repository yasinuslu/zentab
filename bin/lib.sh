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

# xcodebuild and `xcrun swift-format` need a full Xcode, not the bare Command
# Line Tools instance. When `xcode-select` points at CLT (e.g. after a CLT
# update silently flips it back), every Xcode command dies with a cryptic
# "tool 'xcodebuild' requires Xcode" error. Detect that here and fail early
# with the exact one-line fix. We can't run the fix for you: it needs sudo.
ensure_xcode() {
  case "$(xcode-select -p 2>/dev/null || true)" in
    *Xcode*) return 0 ;;  # already pointed at an Xcode.app, nothing to do
  esac

  local xc=""
  for cand in /Applications/Xcode.app /Applications/Xcode-*.app; do
    if [ -d "$cand/Contents/Developer" ]; then xc="$cand"; break; fi
  done

  echo "error: xcode-select points at the Command Line Tools, but the bin/* scripts need full Xcode." >&2
  if [ -n "$xc" ]; then
    echo "Fix it once (needs your password):" >&2
    echo "  sudo xcode-select -s \"$xc/Contents/Developer\"" >&2
  else
    echo "Install Xcode from the App Store, then:" >&2
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  fi
  exit 1
}

# Run xcodebuild, prettifying its output when xcbeautify is installed
# (`brew bundle`). Exit status is preserved either way.
xcb() {
  ensure_xcode
  if command -v xcbeautify >/dev/null 2>&1; then
    set -o pipefail
    xcodebuild "$@" | xcbeautify
  else
    xcodebuild "$@"
  fi
}
