# ZenTab Vision

ZenTab is a free, opinionated macOS window switcher: a focused replacement for
Cmd+Tab and for alt-tab-macos. It switches individual windows, shows a large live
thumbnail grid, and is built so switching is instant. The name is the promise:
calm, focused, zero lag.

## The three-shortcut model (the heart)

| Shortcut | Shows | Scope |
| --- | --- | --- |
| **Cmd+`** (backtick) | windows of the **active app**, everywhere | all Spaces + all monitors (incl. minimized, hidden, fullscreen; the app itself listed last if it has no window) |
| **Cmd+Tab** | **every window here** (all apps, the current app included) | current monitor + visible Space (real on-screen windows only) |
| **Option+Tab** | **everything** | all apps, all Spaces, all monitors (no exclusions: includes the current app, minimized, hidden, windowless apps last) |

Cmd+Tab is the fast everyday switch: what is live right here, on this monitor and
this Space. The current app's windows are *in* that list (excluding them is
disorienting), but the selection starts on the most-recent **other** window, so a
quick tap still switches away from where you are (classic Cmd+Tab). Cmd+` is the
companion for one app: every window of the **active** app, gathered from wherever it
is (other Spaces, other monitors, minimized), so you can fan through them without
hunting. Option+Tab is the only fully global shortcut: the escape hatch for reaching
anything, anywhere. The exact per-mode filters (apps, Spaces, screens, minimized,
hidden, fullscreen, windowless) are fixed and not configurable; only the trigger
keys are.

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
  resolution, HID-level event tap, tap recovery. ZenTab **never silently rebinds to
  another key as a fallback** — it holds the claim relentlessly (re-asserting it on
  a watchdog tick, since other apps / macOS updates / a login can re-enable the
  native hotkey) and **reports honestly in the menu bar** whether it currently owns
  the shortcut. The native shortcut is **auto-restored** whenever our tap is disabled
  (sleep, secure input) or the app crashes/quits, so you are never stranded with a
  dead key. Shipped default is the Cmd+Tab suite; a **development launch profile**
  (`bin/run`) uses safe non-hijacking chords so iterating never touches your Cmd+Tab,
  and `bin/run-prod` exercises the real suite. The trigger keys remain configurable.
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
gone; the app is a menu bar accessory. The shipped default is now the **Cmd+Tab
suite** (`Cmd+Tab` other apps · `Cmd+\`` this app · `Option+Tab` everything); a
development launch profile keeps the safe `Ctrl+Opt+…` chords for day-to-day work
(`bin/run` = dev, `bin/run-prod` = production, both configurable in TOML). On the
configured trigger it:

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

The **native `Cmd+Tab` override is implemented**: the colliding macOS symbolic hotkeys
(`Cmd+Tab` / `Cmd+Shift+Tab` / `Cmd+\``) are disabled via the private
`CGSSetSymbolicHotKeyEnabled` so the event tap can absorb the keystroke, but only once
the tap is live (so we never brick the key when we can't serve it). A 2-second watchdog
re-asserts the claim, re-enables the tap if the OS disabled it, verifies the claim with
`CGSIsSymbolicHotKeyEnabled`, and **restores the native shortcuts** on quit, on crash
(SIGTERM/SIGINT + uncaught-exception guards), or whenever capture isn't possible. The
menu bar icon is the at-a-glance indicator (calm rectangle = we own it, warning triangle
= we don't, with the reason in the dropdown).

**Next:** live thumbnails are wired through ScreenCaptureKit but the grid currently
falls back to app icon + title until that's verified on-device; then the other two modes
(current-app `Cmd+\``, everything `Option+Tab` across Spaces/monitors via the deferred
private CGS calls), W=close / Q=quit, and recency for the tap toggle. The contributor
guide (`CLAUDE.md`) and the local alt-tab reference clone hold the API names.
</content>
