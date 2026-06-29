# ZenTab Vision

ZenTab is a free, opinionated macOS window switcher: a focused replacement for
Cmd+Tab and for alt-tab-macos. It switches individual windows, shows a large live
thumbnail grid, and is built so switching is instant. The name is the promise:
calm, focused, zero lag.

## The three-shortcut model (the heart)

| Shortcut | Shows | Scope |
| --- | --- | --- |
| **Cmd+`** (backtick) | windows of the **current app** | current monitor + current Space |
| **Cmd+Tab** | **every window here** (all apps, the current app included) | current monitor + current Space |
| **Option+Tab** | **everything** | all apps, all Spaces, all monitors (no exclusions: includes the current app, minimized, hidden) |

Cmd+` and Cmd+Tab share the **same locality** (current monitor + current Space):
Cmd+Tab shows every window there, and Cmd+` narrows that to just the current app's
windows. The current app's windows are *in* the Cmd+Tab list (excluding them is
disorienting), but the selection starts on the most-recent **other** window, so a
quick tap still switches away from where you are (classic Cmd+Tab). Option+Tab is
the only global shortcut: the escape hatch for reaching anything, anywhere.

## Interaction

- **Tap (press and release):** instant switch to the single most-recently-used
  other window, no overlay, no lag. The fast path is sacred.
- **Hold the modifier:** the thumbnail grid appears with a **stable** window list
  (each window keeps the same position; never reshuffled by recency). MRU past the
  single most-recent window is fiction and disorienting; a stable list builds
  muscle memory. Recency is used in exactly one place: the quick-tap toggle.

While the overlay is held:

- **Navigate** with Tab (forward) and Shift+Tab (backward), or by **hovering the
  mouse** over a thumbnail. Keyboard and mouse drive one shared selection; the most
  recent input wins.
- **Release the modifier** to focus the selected (hovered) window.
- **W** closes the selected window. **Q** quits its whole app. Small close/quit
  buttons also appear on the thumbnail under the mouse, for discoverability.
- Releasing the key always confirms: if the mouse is over a thumbnail, that one is
  focused; otherwise the keyboard selection stands. Release is never a cancel.

This *behavior* is **not configurable** (it is the opinion ZenTab ships); only the
keys that trigger it are.

## Principles

1. **Performance is the product.** Zero perceptible lag. That is what "Zen" means.
2. **Opinionated and minimal.** The switching *behavior* (the three-mode model,
   tap-vs-hold, the stable list, W/Q) is the permanent opinion and is **not
   configurable** in the MVP; if demand ever forces config, it stays the default
   forever and never changes out of the box. The *key bindings* that trigger each
   mode **are** configurable from the start (in the TOML file): different keys,
   same behavior. This feeds the nixify story and keeps development unblocked (bind
   a non-hijacking key while the native Cmd+Tab override is being hardened).
3. **Config is a file.** A single TOML file is the source of truth: nixifiable,
   git-trackable, watched at runtime. Strong defaults keep it near-empty.
4. **Free forever.** No Pro tier, no license, no server, no nag sequence.

## Technical shape (decided)

- Individual windows, large live thumbnail grid.
- Overlay is hand-rolled **AppKit + CALayer** (NSPanel, recycled tiles) for speed.
  SwiftUI only for non-hot UI (menubar, settings).
- Config in **TOML**.
- **Cmd+Tab replaces** the native switcher (private symbolic-hotkey API). This
  override is a **hard requirement: it must be dependable in every app** (alt-tab
  is flaky here; ZenTab is not). Whatever it takes: deterministic hotkey
  resolution, HID-level event tap, tap recovery. The native shortcut is
  **auto-restored** whenever our tap is disabled (sleep, secure input) or the app
  crashes, so you are never stranded. Shipped default is Cmd+Tab; bindings are
  configurable so a safe key can be used during development.
- **App Sandbox OFF, no Mac App Store** (the feature set requires private
  SkyLight/CGS APIs). Distributed as a DMG / GitHub release. **Notarization is the
  committed end state** (we will ship notarized). Interim: **ad-hoc signed**
  (first-launch Gatekeeper warning) only because the Apple Developer account is
  currently blocked (org account stuck, cannot switch to individual; resolution
  pending, see `docs/HUMAN-TODO.md`). Needs Accessibility permission (mandatory)
  and Screen Recording (for thumbnails).

## Status

**First vertical slice is implemented** (build- and test-verified; runtime needs
Accessibility/Screen Recording granted and is hand-verified). The SwiftUI scaffold is
gone; the app is a menu bar accessory. On a safe, non-hijacking hotkey (default
`Ctrl+Opt+Tab`, configurable in TOML) it:

- enumerates every window on the current monitor + Space (CoreGraphics z-order +
  Accessibility detail), in a stable list, with the selection starting on the
  most-recent other window so a quick tap switches away;
- shows the hand-rolled, non-activating AppKit overlay (`NSPanel` + recycled CALayer
  tiles), with tap-vs-hold (a fast tap switches with no overlay; a hold shows the grid);
- navigates with Tab / Shift+Tab and the mouse (one shared selection), and focuses the
  window on release via the private SLPS front + synthetic-key + AX-raise sequence;
- loads config from `~/.config/zentab/config.toml` (hand-rolled parser, strong defaults).

The private SkyLight/CGS symbols are bound with `@_silgen_name` (no bridging header), and
SkyLight is linked via `-framework SkyLight`; the menu bar has a diagnostics action to
smoke-test the bindings.

**Next:** live thumbnails are wired through ScreenCaptureKit but the grid currently
falls back to app icon + title until that's verified on-device; then the other two modes
(current-app `Cmd+\``, everything `Option+Tab` across Spaces/monitors via the deferred
private CGS calls), W=close / Q=quit, recency for the tap toggle, and finally the native
`Cmd+Tab` override (private symbolic-hotkey API) with auto-restore. The contributor guide
(`CLAUDE.md`) and the local alt-tab reference clone hold the API names.
</content>
