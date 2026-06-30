# ZenTab — Vision

> **ZenTab is not about its interface. It's about the feel, and the focus it brings
> to the user.**
>
> **The full focus is on two co-equal pillars: feel and performance.** They are the same
> goal — a tool that feels instant and calm *is* a fast tool. Everything else is secondary.

ZenTab is **one product with two native implementations**: a macOS app (Swift / AppKit,
in [`darwin/`](darwin/)) and a Windows app (C# / WPF on .NET 10, in [`windows/`](windows/)).
Same philosophy, same branding, native guts on each OS. It is *inspired by*
[alt-tab-macos](https://github.com/lwouis/alt-tab-macos) but takes the **opposite design
philosophy**: where alt-tab answers every question with "make it a setting" (up to 9
shortcuts, each with its own copy of every filter), ZenTab picks one behavior per axis and
**deletes the knob**. The interface is only a means; the goal is a calm, focused switch.

## What "focus" means here

All of these at once:

- **Zero-friction / invisible** — switching never breaks your flow; the tool gets out of the way.
- **Single-tasking by default** — the current task is the center of gravity; everything else feels "put away."
- **Calm, not stimulating** — quiet, unhurried, no jarring motion or loud chrome.
- **Attention directed in the moment** — while you choose, the rest of the world recedes.

Both OSes have the same building block — a **desktop** (a *Space* on macOS, a *virtual
desktop* on Windows) — so the model below reads identically on each; only the terminology
and trigger keys differ.

## The three-mode model (the heart)

Three modes, hard-coded behavior, on every platform. Only the *trigger keys* are
configurable (in the TOML file); the modes themselves are the opinion ZenTab ships.

| Mode | Shows | Scope |
| --- | --- | --- |
| **Everyday switch** | every window here — all apps, the current app included | current monitor + current desktop (real on-screen windows only) |
| **Current-app windows** | every window of the active app, gathered from wherever it is | all desktops + all monitors (incl. minimized, hidden, fullscreen; the app listed last if it has no window) |
| **Global escape hatch** | *everything* — the "I lost something" valve | all apps, all desktops, all monitors |

The everyday switch is the fast one you reach for constantly: what's live right here, on
this monitor and this desktop. The current app's windows are *in* that list (hiding them is
disorienting), but the selection starts on the most-recent **other** window, so a quick tap
still switches away from where you are. Current-app mode is the companion for one app: every
window of the active app, gathered from wherever it is — other desktops, other monitors,
minimized — so you can fan through them without hunting. The escape hatch is the only fully
global mode: the pressure-release valve for reaching anything, anywhere.

**Native key bindings** (defaults — the trigger keys, and only the keys, are configurable):

| Mode | macOS | Windows |
| --- | --- | --- |
| Everyday switch | **Cmd + Tab** | **Alt + Tab** |
| Current-app windows | **Cmd + `** | **Alt + `** |
| Global escape hatch | **Option + Tab** | **Ctrl + Alt + Tab** |

> `Shift` is reserved everywhere for reverse navigation, so it never appears in a trigger.

Each platform expresses the model in its native keys. The behavior and scopes above are the
spec for both; where an implementation lags today (e.g. Windows' everyday list is per-app
for now, not per-window), that's an implementation gap to close — see **Status** — not a
competing opinion.

## Interaction

- **Tap (press and release):** instant switch to the single most-recently-used other
  target, no overlay, no lag. The fast path is sacred — and it works even though the
  visible list uses stable order, so blind tap-toggle between two things still works.
- **Hold the modifier:** the overlay appears with a **stable** list — each entry keeps the
  same position, never reshuffled by recency, so you build spatial muscle memory ("Slack is
  always 4th"). MRU past the single most-recent entry is fiction and disorienting; recency
  is used in exactly one place: the quick-tap toggle.

While the overlay is held:

- **Navigate** with Tab (forward) / Shift+Tab (backward), or by **hovering the mouse**.
  Keyboard and mouse drive one shared selection; the most recent input wins.
- **Release the modifier to commit** to whatever is highlighted. Release is never a cancel.
- **Click outside** the overlay to stop switching with no focus change — the one cancel
  gesture, distinct from release-to-commit.
- **W** closes the selected window; **Q** quits its whole app. Small close/quit affordances
  also appear on the entry under the mouse, for discoverability.

This *behavior* is **not configurable** — it is the opinion ZenTab ships. Only the keys
that trigger each mode are.

## Principles

1. **Performance is the product.** Zero perceptible lag. That is what "Zen" means.
2. **Opinionated and minimal.** The switching behavior (the three-mode model, tap-vs-hold,
   the stable list, W/Q) is permanent and **not configurable**. The default answer to
   "should this be a setting?" is **no**. Only the trigger key bindings are configurable.
3. **Config is a file.** A single TOML file is the source of truth: nixifiable,
   git-trackable, watched at runtime. Strong defaults keep it near-empty.
4. **Free forever.** No Pro tier, no license server, no nag sequence.

## Performance is a feature

Feel and performance are inseparable: the soft fade, the dim+blur, the instant appearance —
none of it feels calm if it stutters. Performance is a first-class pillar, not a later
optimization. Every design and implementation choice is judged against it.

- **Imperceptible summon latency.** The overlay begins its fade the moment the shortcut
  fires. Don't enumerate windows or build thumbnails cold on the keypress — keep
  window/app state pre-warmed in the background so showing is near-instant.
- **The input hook must never add lag.** A low-level keyboard hook / event tap sits in the
  system input path; its callback returns immediately and does real work off the hot path.
  A slow hook degrades typing system-wide — unacceptable.
- **GPU, not CPU, for visuals.** Composited live thumbnails (DWM on Windows,
  ScreenCaptureKit + CALayer on macOS) over CPU screenshots, and a GPU-backed backdrop for
  the dim+blur. No per-frame CPU bitmap work.
- **Smooth at the monitor's refresh rate.** No jank, no dropped frames, no GC/allocation
  pauses during the interaction. Animations target the display's actual refresh (120/144Hz,
  not 60). Motion is a quick, soft fade (~80–120 ms): calm but not slow.
- **Near-zero idle cost.** ZenTab is resident all day. When not summoned it is effectively
  invisible to CPU, GPU, and memory — no polling spin, minimal working set.

## In-overlay actions

Only two: **close window** (W) and **quit app** (Q). Nothing else — no minimize,
fullscreen, or hide. Window management is the OS's job.

## Deliberately out of scope

- **Switching desktops** — moving between Spaces / virtual desktops is the OS's job
  (Mission Control, `Win + Ctrl + ←/→`). ZenTab switches *windows*, not desktops — even
  when current-app or escape-hatch mode reaches across desktops to focus one.
- **Active single-tasking mechanisms** — no clutter warnings, no forced receding of other
  windows. The tight scoping *is* the nudge.
- **Configurability** — there is intentionally almost nothing to configure beyond the
  trigger keys.

## Platform implementations

### macOS (`darwin/`)

- Hand-rolled **AppKit + CALayer** overlay (`NSPanel`, recycled tiles) for speed; SwiftUI
  only for non-hot UI (menu bar). Switches **individual windows** — the everyday Cmd+Tab
  list is per-window (the current app's windows included, selection starting on the most
  recent *other* window so a quick tap still switches away).
- **Cmd+Tab replaces the native switcher** via the private `CGSSetSymbolicHotKeyEnabled`
  API — a hard requirement that must be dependable in every app. ZenTab never silently
  rebinds to a fallback key: it holds the claim on a watchdog tick, reports honestly in the
  menu bar whether it owns the shortcut, and **auto-restores** the native shortcut whenever
  capture is disabled or the app quits/crashes, so you're never stranded.
- Private SkyLight/CGS + Accessibility SPIs via `@_silgen_name`. **App Sandbox OFF**, no Mac
  App Store. **Notarization is the committed end state**; interim builds are ad-hoc signed
  (Gatekeeper warning) only because the Apple Developer account is currently blocked (see
  `darwin/docs/HUMAN-TODO.md`). Needs Accessibility (mandatory) + Screen Recording (thumbnails).

### Windows (`windows/`)

- **C# / WPF on .NET 10** with a thin Win32/DWM interop layer (`Native.cs`). Resident in
  the tray (no main window). The everyday Alt+Tab list is **per-app today** (one entry per
  app) — a known gap from the per-window spec above, kept for now because it matches the
  Windows habit; closing it is tracked in Status.
- **Replaces native Alt+Tab entirely** via a low-level keyboard hook. **Live thumbnails via
  DWM**; the world behind the overlay **dims + blurs** (all monitors) to spotlight the
  choices.
- Ships as a self-contained portable exe + WiX MSI.

## Status

- **macOS** — first vertical slice implemented (build/test-verified; runtime hand-verified
  with Accessibility/Screen Recording granted). Menu bar accessory; the Cmd+Tab native
  override is implemented (disable native symbolic hotkeys, event-tap capture, watchdog
  re-assert, restore-on-quit/crash). Live thumbnails are wired through ScreenCaptureKit but
  the grid falls back to icon+title until verified on-device. Next: the other two modes
  across Spaces/monitors, and recency for the tap toggle.
- **Windows** — overlay, keyboard hook, per-app Alt+Tab, live thumbnails, and packaging
  (portable exe + MSI + checksums) are in place. See `windows/docs/review-notes.md` for the
  open backlog. **Gaps from the spec above:** the everyday list is per-app (should be
  per-window), `Alt+\`` reaches only the current desktop (should reach all), and minimized
  windows are excluded from current-app/escape-hatch modes (should be included).
