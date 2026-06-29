# ZenTab — Vision

> **ZenTab is not about its interface. It's about the feel, and the focus it brings to the user.**
>
> **The full focus is on two things: feel and performance.** They are the same goal —
> a tool that feels instant and calm *is* a fast tool. Everything else is secondary.

ZenTab is a Windows Alt+Tab alternative (C# / WPF on .NET 10, with a thin Win32/DWM
interop layer). It is *inspired by* [alt-tab-macos](https://github.com/lwouis/alt-tab-macos)
but takes the **opposite design philosophy**.

alt-tab-macos answers every design question with "make it a setting" — up to 9
independent shortcuts, each with its own copy of every filter and appearance option.
ZenTab is **very opinionated**: for each axis we pick one behavior and *delete the knob*.
The interface is only a means; the goal is a calm, focused switching experience.

## What "focus" means here

It means all of these at once:

- **Zero-friction / invisible** — switching never breaks your flow; the tool gets out of the way.
- **Single-tasking by default** — the current task is the center of gravity; everything else feels "put away."
- **Calm, not stimulating** — quiet, unhurried, no jarring motion or loud chrome.
- **Attention directed in the moment** — while you choose, the rest of the world recedes.

### Spaces are separate universes

Switching virtual desktops means switching your *whole world*, on purpose. Reaching
into another desktop to grab a single window is, by design, considered the wrong move —
there's a reason you put something in another universe. This principle is why the
everyday modes never cross desktops.

## The three modes (hard-coded, not configurable)

| Shortcut | Shows | Scope |
| --- | --- | --- |
| **Alt + Tab** | apps — one entry per app | current monitor + current virtual desktop |
| **Alt + `** (tilde) | windows of the current/foreground app | current desktop (all monitors) |
| **Ctrl + Alt + Tab** | *everything* — the "I lost something" escape hatch | all monitors, all desktops |

The everyday modes (Alt+Tab, Alt+`) stay pure and tightly scoped. Ctrl+Alt+Tab is the
only mode that crosses universes — the pressure-release valve for the rare moment you've
misplaced something.

> Not `Alt+Shift+Tab` — Shift is reserved for reverse navigation.

## Interaction

- **Replaces native Alt+Tab entirely** (low-level keyboard hook).
- **Hold to cycle, release Alt to commit.**
- Selection follows **both Tab and the mouse** — last input wins; releasing Alt commits
  to whatever is currently highlighted.
- **Quick tap** (release before touching the mouse) jumps to the **most-recently-used
  previous** app, so blind tap-toggle between two apps still works — even though the
  visible list uses stable order.

## Ordering & list content

- **Stable order** (by launch/creation order), *not* MRU display order — so you build
  spatial muscle memory ("Slack is always 4th").
- **Minimized windows are excluded entirely** — you put them away on purpose; the taskbar
  brings them back.

## Feel

- When the overlay is up, the world behind it **dims + blurs** (all monitors) — spotlight
  the choices.
- **Live thumbnails** (DWM).
- Motion is a **quick, soft fade (~80–120 ms)** — calm but not slow; not instant-jarring,
  not heavy/springy.

## Performance is a feature

Feel and performance are inseparable: the soft fade, the dim+blur, the instant appearance
— none of it feels calm if it stutters. Performance is therefore a first-class pillar, not
an optimization to do later. Every design and implementation choice is judged against it.

Targets and principles:

- **Imperceptible summon latency.** The overlay must begin its fade the moment the
  shortcut fires. Don't enumerate windows or build thumbnails cold on the keypress —
  keep window/app state pre-warmed and updated in the background so showing is near-instant.
- **The keyboard hook must never add input lag.** A low-level hook sits in the system input
  path; its callback has to return immediately and do real work off the hot path. A slow
  hook degrades typing system-wide — unacceptable.
- **GPU, not CPU, for visuals.** Use DWM live thumbnails (composited, cheap) over CPU
  screenshots, and a GPU-backed backdrop (acrylic / composition blur) for the dim+blur.
  No per-frame CPU bitmap work.
- **Smooth at the monitor's refresh rate.** No jank, no dropped frames, no GC pauses during
  the interaction. Animations target the display's actual refresh (120/144Hz, not 60).
- **Near-zero idle cost.** ZenTab is resident all day. When not summoned it should be
  effectively invisible to CPU, GPU, and memory — no polling spin, minimal working set.
- **Fast, lean process.** Quick start, small footprint. Avoid heavyweight abstractions that
  buy configurability we don't want (see philosophy) at the cost of speed.

## In-overlay actions

Only two: **close window** and **quit app**. Nothing else (no minimize, fullscreen, or
hide). Window management is the OS's job.

## Deliberately out of scope

- **Switching virtual desktops** ("universes") — left to Windows (`Win + Ctrl + ←/→`).
  ZenTab only switches *within* the current universe, plus the global escape hatch.
- **Active single-tasking mechanisms** — no clutter warnings, no forced receding of other
  windows. The tight scoping *is* the nudge.
- **Configurability** — there is intentionally almost nothing to configure.

## Open edges (current defaults, not yet explicitly confirmed)

These are leaning a certain way but haven't been locked:

1. **Alt+`'s scope** — current app's windows across *this universe* (current desktop, all
   monitors). _Default: current desktop, all monitors._
2. **Dim+blur reach** — _Default: all monitors recede, not just the active one._
3. **What "stable order" keys off** — _Default: launch/creation order_ (truly stable;
   Z-order would shuffle as you use windows).
