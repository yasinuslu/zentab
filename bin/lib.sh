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

# Path to the built Debug .app bundle. Reads it from xcodebuild's resolved settings
# (captured separately from the build so its output never pollutes the path).
debug_app_path() {
  local settings dir name
  settings="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Debug -destination "$DESTINATION" -showBuildSettings 2>/dev/null)"
  dir="$(printf '%s\n' "$settings" | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' | head -1)"
  name="$(printf '%s\n' "$settings" | sed -n 's/^ *FULL_PRODUCT_NAME = //p' | head -1)"
  printf '%s/%s\n' "$dir" "$name"
}

# Build (Debug), then quit any running instance and relaunch, passing the given args
# through to the app (e.g. `-profile dev`). We must relaunch — `open` only forwards
# `--args` to a fresh process, so a switch of launch profile needs the old one gone.
# Quitting via SIGTERM also triggers the app's restore of the native Cmd+Tab.
build_and_launch() {
  xcb build \
    -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Debug -destination "$DESTINATION" \
    CODE_SIGNING_ALLOWED=NO

  local app
  app="$(debug_app_path)"

  if pgrep -x ZenTab >/dev/null 2>&1; then
    pkill -x ZenTab 2>/dev/null || true
    for _ in $(seq 1 30); do
      pgrep -x ZenTab >/dev/null 2>&1 || break
      sleep 0.1
    done
  fi

  echo "Launching $app $*"
  open "$app" --args "$@"
}
