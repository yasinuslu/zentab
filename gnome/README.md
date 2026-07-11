# ZenTab

**An opinionated Alt+Tab alternative for GNOME Shell.** TypeScript compiled to a single GJS
ESM bundle, running entirely in-process inside `gnome-shell` — no daemon, no D-Bus, no
protocol of its own.

> ZenTab is not about its interface — it's about the **feel**, and the **focus** it brings.
> It is *very* opinionated: for each choice we pick one behavior and delete the knob. See
> [`../VISION.md`](../VISION.md).

> **ZenTab is a cross-platform vision, not a single app.** The product — the *feel*, the
> *focus*, the brand — is shared across platforms; each platform gets a native implementation
> that does whatever is best *there*. This folder is the **GNOME Shell** edition; the
> **macOS** edition (native Swift) lives in [`../darwin/`](../darwin/) and the **Windows**
> edition (C#/WPF) in [`../windows/`](../windows/). Same philosophy
> ([`../VISION.md`](../VISION.md)), same brand ([`../BRANDING.md`](../BRANDING.md)), different
> native guts.

## What it does

| Gesture | Shows | Scope |
| --- | --- | --- |
| **Alt + Tab** | every window, all apps | current monitor + current workspace |
| **Alt + `** | every window of the active app | all workspaces, all monitors (incl. minimized) |
| **Ctrl + Alt + Tab** | everything — the "I lost something" escape hatch | all apps, all workspaces, all monitors |

- **Quick tap = instant switch.** Tap and release within `hold_threshold_ms` (default 150 ms)
  and ZenTab switches straight to your previous window — the overlay never even appears. Hold
  past the threshold, or tap again, to reveal it.
- **Hold to cycle, release to commit.** Tab advances, Shift+Tab reverses; releasing the chord's
  modifier switches to the selected window. Escape cancels. (Deliberately Tab/Shift+Tab only,
  per VISION — no arrow-key alias: the tile grid wraps into rows, so "Down" would stop meaning
  "the tile below" the moment a session has more than one row.)
- **Mouse hover selects too.** Move over a tile to select it, click to commit immediately, or
  click outside the card to cancel.
- **Stable order** (first-seen, never MRU-reshuffled) so you build muscle memory — "Slack is
  always 4th." Recency (MRU) is used only to pick the *initial* highlighted tile on summon.
- **In-overlay actions**: **W** closes the selected window, **Q** quits its app. Nothing else
  — no minimize, no fullscreen, no hide.
- **ZenTab supersedes GNOME's own switcher** the moment it's enabled — Alt+Tab, Alt+`, and
  Ctrl+Alt+Tab all become ZenTab's gestures, reversibly (see [How it works](#how-it-works)).

Window state is kept warm off the hot path via display/workspace signals — summoning the
overlay never does a cold `global.get_window_actors()` walk, and idle cost is near zero
(event-driven, no polling timers).

## GNOME version support and caveat

Targets **GNOME Shell 50.2 on Wayland**, using the modern ESM extension format (GNOME 45+:
`export default class extends Extension`, no legacy `imports.*`). `metadata.json` declares
`shell-version: ["48", "49", "50"]`. The one area most likely to need adjustment on a shell
version ZenTab hasn't been run against is `keybinding.ts`'s override of GNOME's own switcher
handlers (`Main.wm.setCustomKeybindingHandler`, `_startSwitcher` / `_startA11ySwitcher`) and
`switcher.ts`'s modal-grab plumbing (`Clutter.KeyController`, `Main.pushModal`/`popModal`) —
both are internal, undocumented GNOME Shell APIs that have moved across 42→45→50 and could
move again. If ZenTab stops claiming the gestures cleanly on a future shell version, these two
files are where to start.

**Wayland caveat (not a ZenTab bug, affects stock GNOME identically):** Mutter honors the
`zwp_keyboard_shortcuts_inhibit_unstable_v1` protocol — any native Wayland client that requests
exclusive keyboard access (a fullscreen game via Steam/gamescope, a VM viewer, a remote-desktop
session) makes Mutter stop dispatching ordinary compositor keybindings system-wide while that
surface holds the grab. Only a small system-critical allow-list survives it. While that
inhibitor is held, Alt+Tab / Alt+\` / Ctrl+Alt+Tab simply never reach ZenTab — no error, no log
line, nothing in the overlay, and there is no in-extension hook to detect it (the key event
never arrives at all). This is Mutter policy no extension can override; the honest fix is this
paragraph, not code. If your gestures "stop working" only while a specific fullscreen app or VM
window has focus, this is almost certainly why.

## Install

Build the bundle yourself (no releases are published for this platform yet):

```bash
npm install
npm run typecheck      # tsc --noEmit
npm run build          # esbuild -> dist/extension.js, dist/schemas/gschemas.compiled
```

Or run the whole pipeline in one step: `bin/zentab-build` (typecheck → esbuild bundle →
a second, source-tree-only `glib-compile-schemas schemas` as a pure well-formedness check;
this second compile is gitignored and never shipped — the one under `dist/schemas/` that
GNOME Shell actually reads is produced by `esbuild.js` itself).

> `glib-compile-schemas` must be on `PATH`. It ships as part of `glib` on virtually every
> Linux desktop; if you're on a system where it isn't (e.g. a minimal Nix dev shell), it lives
> in the `glib.dev` output — `nix shell nixpkgs#glib.dev` — since Nix splits `bin` and `dev`
> outputs differently than most distros.

Then symlink `dist/` into GNOME's extensions directory:

```bash
bin/zentab-install     # symlinks dist/ -> ~/.local/share/gnome-shell/extensions/zentab@zentab.app
gnome-extensions enable zentab@zentab.app
```

On Wayland, a newly-installed extension typically needs a log out/in before GNOME Shell
notices it exists; on X11, Alt+F2 → `r` → Enter reloads the shell in place instead.
`bin/zentab-install` only creates a symlink — it never reloads or restarts `gnome-shell`
itself, and never touches gsettings/dconf (that only happens once the extension is actually
enabled and running, via `config.ts`'s write-through).

## Dev loop

Rebinding the real Alt+Tab while iterating is risky, so develop inside a **nested** GNOME
Shell session instead of your real one:

```bash
dbus-run-session -- gnome-shell --nested --wayland
```

That opens a second, fully separate Wayland compositor in a window. Install and enable ZenTab
*inside that nested session* (run `bin/zentab-install` and `gnome-extensions enable
zentab@zentab.app` from a terminal launched inside it), then iterate: edit source, run
`bin/zentab-build`, close and relaunch the nested shell to pick up the new `dist/extension.js`
(a plain extension reload isn't enough for an ESM bundle rewritten on disk).

`bin/zentab-dev` documents this loop without running it for you — a nested compositor is a
real, separate GPU-composited session, not a lightweight sandbox, so launch it yourself,
deliberately, in a terminal you're actively watching. Never run it unattended, and never while
your real session needs to stay maximally responsive (e.g. while gaming).

## Configuration

ZenTab is intentionally opinionated — the three modes' *behavior* is fixed and not
configurable (VISION.md). The only knobs are the three **trigger chords** and the **hold
threshold**, in a single TOML file at `~/.config/zentab/config.toml`. With no file present,
the shipping defaults apply.

```toml
[keys]
other_apps  = "alt+tab"        # everyday switch — current monitor + current workspace
current_app = "alt+`"          # windows of the current app, all workspaces + monitors
everything  = "ctrl+alt+tab"   # the "I lost something" escape hatch

[behavior]
hold_threshold_ms = 150        # hold past this to reveal the overlay; a quicker tap-and-
                               # release switches invisibly
```

This mirrors [`../windows/zentab.toml`](../windows/zentab.toml)'s schema exactly. GJS ships no
TOML library, so `config.ts` hand-rolls just enough of the format for these two flat sections
(no arrays, no tables-of-tables) — deliberately, since the schema never grows past this per
VISION's "delete the knob" principle. Chord strings are parsed into GNOME accelerator form
(`"alt+tab"` → `"<Alt>Tab"`) and written through into the extension's private `Gio.Settings`
(schema `org.gnome.shell.extensions.zentab`) so `Main.wm.addKeybinding` has a GSettings-backed
key to read; `Gio.FileMonitor` live-reloads the file on every save, no restart needed. There is
no prefs dialog and no other knob.

## How it works

- **Claiming the gestures** (`keybinding.ts`): `Main.wm.setCustomKeybindingHandler` supersedes
  GNOME's own `switch-applications(-backward)` / `switch-windows(-backward)` (→ everyday
  switch), `switch-group(-backward)` (→ current-app windows), and `switch-panels(-backward)`
  (→ global escape hatch, the one that collides with the default Ctrl+Alt+Tab). This replaces
  only what happens when the binding fires — it never mutates the user's stored keybindings —
  so it's fully reversible in `disable()`. A configured chord with no built-in match instead
  gets its own private `Main.wm.addKeybinding` against ZenTab's own gschema.
- **The window model** (`windows.ts`): a pre-warmed `WindowSnapshotService` primes once from
  `global.get_window_actors()`, then stays current via `window-created` / each window's own
  `unmanaging` signal, with a few cheap additive-only self-heal passes for the rare compositor
  race (a window that appears without `window-created` firing for it): `active-workspace-changed`
  and `monitors-changed` react eagerly, while the more frequent `restacked` case is instead
  reconciled lazily at the top of `getEntries()` — right before a switch session actually opens
  — rather than on every restack (an ordinary, frequent desktop event unrelated to the rare race
  it would be guarding). Only *identity* and *first-seen order* are cached — everything else
  (monitor, workspace, minimized, title) is always read live off `Meta.Window` at query time.
- **The interaction state machine** (`switcher.ts`): tap-vs-hold via a `GLib.timeout_add` on
  `hold_threshold_ms`, a modal grab via `Main.pushModal`/`Clutter.Grab`, and a
  `Clutter.KeyController` for Tab/Shift+Tab selection and release-to-commit (watching the
  chord's primary modifier bit clear, the same reduction GNOME's own `switcherPopup.js` uses).
  `Switcher` owns one persistent, invisible, full-stage grab actor for its whole lifetime
  (`Main.pushModal`/`popModal` re-grab and release it once per session) rather than creating a
  fresh actor per session — `switcherPopup.js` itself grabs a single actor that is *both* the
  grab target and the visible/interactive UI, so ZenTab's overlay is parented as a descendant of
  that same actor (`OverlayView.attachTo()`) instead of living in a sibling subtree; a modal
  grab only delivers pointer events (hover, click) to the grabbed actor's own descendants.
- **The overlay** (`overlay.ts`, `theme.ts`): a full-screen `St.Widget` scrim plus one card of
  tiles, parented under `Switcher`'s grab actor (see above) and rendered on the monitor under
  the cursor. v1 ships icon + title identification only — a plain dim scrim rather than a GPU
  blur-behind, and no live window thumbnail — both explicitly deferred with `TODO(blur)` /
  `TODO(thumbnail)` hooks in the source. Every color/radius/spacing value is transcribed from
  [`../BRANDING.md`](../BRANDING.md), never invented locally.
- **Config** (`config.ts`): load → resolve (per-field fallback to defaults) → write-through to
  `Gio.Settings` → watch for live-reload, as described above.
- **Entry point** (`extension.ts`): `enable()` wires config → windows → overlay → switcher →
  keybindings, in that order (each stage depends on the ones before it); `disable()` tears
  everything down in exact reverse order — every signal disconnected, every actor removed and
  destroyed, every keybinding removed and every overridden handler restored, all references
  nulled. No work happens at module import time, and the extension must survive being disabled
  at the lock screen.

## Source layout

- `src/model.ts` — shared types: `Mode`, `WindowEntry`, `Config`, `OverlayAction`
- `src/util.ts` — `log`/`logError`, `SignalBag` (tracked-connection teardown), `assert`
- `src/config.ts` — TOML parsing, chord → accelerator resolution, `ConfigManager`
- `src/windows.ts` — `WindowSnapshotService`, the pre-warmed window model
- `src/theme.ts` — brand tokens transcribed from `BRANDING.md`
- `src/overlay.ts` — `OverlayView`, the scrim + card + tile actor tree
- `src/switcher.ts` — `Switcher`, the tap/hold/grab/commit state machine
- `src/keybinding.ts` — `KeybindingController`, claiming the native gestures
- `src/extension.ts` — `enable()`/`disable()` wiring, the only module GNOME Shell imports
- `esbuild.js` — bundles `src/extension.ts` → `dist/extension.js`, stages `dist/schemas/`
- `schemas/org.gnome.shell.extensions.zentab.gschema.xml` — the three keybinding accelerators
  only; every other setting lives purely in `config.toml`, never in dconf
- `bin/zentab-build` / `bin/zentab-install` / `bin/zentab-dev` — build, install, and
  (documentation-only) dev-loop scripts

## License

[GPL-3.0](../LICENSE) © Yasin Uslu. Repo-wide, across all platforms.

## Not yet done (next steps)

- **Blur-behind on the scrim** (`TODO(blur)` in `theme.ts`/`overlay.ts`) — a real GPU
  blur-behind to match the website's and macOS's recede effect, once a cheap St/Clutter blur
  path exists.
- **Live window thumbnails** (`TODO(thumbnail)` in `overlay.ts`) — a `Clutter.Clone` of each
  window's texture in the tile, matching the Windows edition's DWM thumbnails.
- **Digit 1–9 jump-to-tile** — present in the macOS/Windows editions, not yet implemented here;
  the index chip renders but isn't wired to a key yet (VISION.md is silent on whether it should
  be — a product call, not an oversight).
- **A packaged release** — no `gnome-vN*` CI/release workflow or `ego` (extensions.gnome.org)
  submission yet; today this is a build-it-yourself extension.
- **Live-shell verification** — see [`docs/HUMAN-TODO.md`](docs/HUMAN-TODO.md) for everything
  in this codebase that was verified by theory (reading current GNOME source/`@girs` types)
  rather than by running the shell, under this pass's machine-safety constraint, and the exact
  gestures/edge cases to exercise in a nested session before relying on ZenTab day-to-day.
