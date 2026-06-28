# ZenTab Vision

ZenTab is a free, opinionated macOS window switcher: a focused replacement for
Cmd+Tab and for alt-tab-macos. It switches individual windows, shows a large live
thumbnail grid, and is built so switching is instant. The name is the promise:
calm, focused, zero lag.

## The three-shortcut model (the heart)

| Shortcut | Shows | Scope |
| --- | --- | --- |
| **Cmd+`** (backtick) | windows of the **current app** | the app you are in |
| **Cmd+Tab** | windows of **other apps** | current monitor + current Space, **excluding the current app** |
| **Option+Tab** | **everything** | all apps, all Spaces, all monitors |

Cmd+` and Cmd+Tab are complementary halves: Cmd+` owns your current app's
windows, so Cmd+Tab drops the current app and shows only other apps nearby.
Option+Tab is the global escape hatch.

## Interaction

- **Tap (press and release):** instant switch, no overlay, no lag. The fast path
  is sacred.
- **Hold the modifier:** the thumbnail grid appears with a **stable** window list
  (each window keeps the same position; never reshuffled by recency). MRU past the
  single most-recent window is fiction and disorienting; a stable list builds
  muscle memory. Recency is used in exactly one place: the quick-tap toggle.

This behavior is **not configurable**. It is the opinion ZenTab ships.

## Principles

1. **Performance is the product.** Zero perceptible lag. That is what "Zen" means.
2. **Opinionated and minimal.** Core switching is one default, not a settings matrix.
3. **Config is a file.** A single TOML file is the source of truth: nixifiable,
   git-trackable, watched at runtime. Strong defaults keep it near-empty.
4. **Free forever.** No Pro tier, no license, no server, no nag sequence.

## Technical shape (decided)

- Individual windows, large live thumbnail grid.
- Overlay is hand-rolled **AppKit + CALayer** (NSPanel, recycled tiles) for speed.
  SwiftUI only for non-hot UI (menubar, settings).
- Config in **TOML**.
- **App Sandbox OFF, no Mac App Store** (the feature set requires private
  SkyLight/CGS APIs). Ships as a notarized DMG / GitHub release. Needs
  Accessibility permission (mandatory) and Screen Recording (for thumbnails).

## Still to decide

1. Cmd+` scope: all Spaces/monitors, or just current?
2. Option+Tab: include current app and minimized/hidden, or exclude some?
3. Tap toggle target: confirm quick-tap goes to the single most-recent other window.
4. Cmd+Tab empty case: empty overlay vs fall-through.
5. Cmd+Tab safety: auto-restore native on tap-death/crash vs hard replace.
6. Code signing: ad-hoc (Gatekeeper warning) vs paid Developer ID + notarization.
</content>
