# ZenTab

**An opinionated Alt+Tab alternative for Windows.** C# + WPF on .NET 10, with a thin
Win32/DWM interop layer.

> ZenTab is not about its interface — it's about the **feel**, and the **focus** it brings.
> The whole focus is two co-equal pillars: **feel and performance**. It is *very*
> opinionated: for each choice we pick one behavior and delete the knob. See
> [`../VISION.md`](../VISION.md).

ZenTab is resident in the tray (no main window) and **replaces the native switching
gestures** with a low-level keyboard hook.

> **ZenTab is a cross-platform vision, not a single app.** The product — the *feel*, the
> *focus*, the brand — is shared across platforms; each platform gets a native
> implementation that does whatever is best *there*. This folder is the **Windows** edition
> (C#/WPF); the **macOS** edition (native Swift) lives in [`../darwin/`](../darwin/) in the
> same repo. Same philosophy ([`../VISION.md`](../VISION.md)), same brand
> ([`../BRANDING.md`](../BRANDING.md)), different native guts.

## What it does

| Gesture | Shows | Scope |
| --- | --- | --- |
| **Alt + Tab** | apps — one entry per app | monitor under the cursor |
| **Alt + `** | windows of the current app | current desktop, all monitors |
| **Ctrl + Alt + Tab** | everything — the "I lost something" escape hatch | all monitors, all desktops |

- **Quick tap = instant switch.** Tap and release within ~150 ms (the `hold_threshold_ms`
  config) and ZenTab switches straight to your previous window — the overlay never even
  appears (just like native Alt+Tab). Hold past the threshold, or tap again, to reveal it.
- **Hold to cycle, release to commit.** Tab / `→` advance, Shift+Tab / `←` reverse;
  releasing the modifier switches to the selected window.
- **Mouse hover selects too.** Move over a card to select it, then release to switch (or
  click to switch immediately). Keyboard and mouse share one selection; last input wins.
- **Live DWM thumbnails** in a floating panel on the **monitor under the cursor**, over a
  dimmed, GPU-blurred backdrop so the rest of the world recedes.
- **Stable order** (by first-seen) so you build muscle memory; initial selection is the
  **MRU-previous** entry so blind tap-toggling between two apps works.
- **Minimized windows are excluded** (use the taskbar to restore them).
- In-overlay actions (VISION.md): **W** closes the selected window, **Q** quits the app,
  **1–9** jump straight to a tile, **Esc** dismisses.

Performance is a feature: window state is pre-warmed in the background, so a warm summon
costs well under a millisecond; the keyboard hook does only cheap work on the input path;
idle cost is near zero (one foreground event hook, no polling).

## Install

**Download** the portable exe or the MSI from the
[Releases](https://github.com/yasinuslu/zentab/releases) page (published automatically when a
`windows-v*` tag is pushed). Each release includes a `SHA256SUMS.txt` — verify a download with:

```powershell
(Get-FileHash .\ZenTab-0.1.0-win-x64.msi -Algorithm SHA256).Hash.ToLower()
# compare against the matching line in SHA256SUMS.txt
```

Or build the artifacts yourself — `build.ps1` produces both in `dist/`:

```powershell
./build.ps1                     # both: portable exe + MSI installer
./build.ps1 -Target portable    # just the portable single-file exe
./build.ps1 -Target installer   # just the MSI
./build.ps1 -Version 0.2.0      # stamp a version into the exe, MSI, and filenames
```

| Artifact | What it is |
| --- | --- |
| `dist/ZenTab-0.1.0-win-x64-portable.exe` | **Truly portable** — one self-contained file. Copy it anywhere and double-click; no .NET install, no setup, no files beside it. |
| `dist/ZenTab-0.1.0-win-x64.msi` | **Installer** — installs to *Program Files*, adds a Start Menu shortcut, and starts ZenTab at login. Quit anytime from the tray icon's menu. |

Both bundle a **self-contained** build, so .NET does not need to be installed on the target
machine, and both use the real Alt+Tab / Alt+` / Ctrl+Alt+Tab gestures (the portable exe
ships without `zentab.toml`, and with no `%APPDATA%\zentab\config.toml` the built-in defaults
apply — see [Configuration](#configuration)).

> Heads-up: this is an early build (0.1.0). The artifacts are unsigned, so SmartScreen may
> warn on first run.

## Build & run from source

```powershell
dotnet run            # run it (framework-dependent, fast inner loop)
dotnet watch run      # hot-reload loop (or ./dev.ps1)
dotnet build          # build only
dotnet publish -c Release -r win-x64   # self-contained single-file exe -> bin/Release/.../publish
```

### Dev mode — test without hijacking the real Alt+Tab

Rebinding global Alt+Tab while you work is risky, so the source tree's `zentab.toml` ships
with safe Ctrl+Alt chords (see [Configuration](#configuration)). `dotnet run` copies it next
to the build output; the published exe and MSI exclude it, so a shipped ZenTab uses the real
gestures. Hold **Ctrl+Alt**, tap **Tab** to cycle apps (**Shift+Tab** to go back), or use the
**mouse**, then release to switch. The active scheme shows in the tray tooltip and menu.

## Configuration

ZenTab is intentionally opinionated — the switching *behavior* is fixed and not configurable
(VISION.md). The only knobs are the three **trigger chords** and the **hold threshold**, in a
single TOML file. With no file present, the shipping defaults apply.

ZenTab reads the first of:

1. `zentab.toml` beside the exe or in the working directory — a portable / dev override.
2. `%APPDATA%\zentab\config.toml` — the standard per-user config.

```toml
[keys]
other_apps  = "alt+tab"        # everyday switch — apps on the monitor under the cursor
current_app = "alt+`"          # windows of the current app
everything  = "ctrl+alt+tab"   # the "I lost something" escape hatch

[behavior]
hold_threshold_ms = 150        # hold past this to reveal the overlay; a quicker tap-and-
                               # release switches invisibly
```

Chords combine `ctrl` / `alt` / `win` with a key (`Tab`, `` ` ``, `F1`–`F24`, a letter or a
digit). `Shift` is reserved everywhere for reverse navigation, so it never appears in a
trigger.

## How it works

- `Native.cs` — Win32/DWM P/Invoke (enumeration, hooks, monitors, thumbnails, activation)
- `WindowService.cs` — warm window state: stable order, MRU, per-mode scoping, entry build
- `KeyboardHook.cs` — low-level keyboard hook + gesture detection (lean callback)
- `SwitcherController.cs` — orchestration, including the quick-tap threshold
- `OverlayWindow.xaml` / `.cs` — the frosted card panel (header, tiles, footer) with live
  thumbnails; `App.xaml` holds the shared brand palette (see [`../BRANDING.md`](../BRANDING.md))
- `DimWindow.cs` — the dimmed, GPU-blurred recede layer behind the panel
- `Config.cs` / `zentab.toml` — the TOML config (trigger chords + hold threshold)
- `App.xaml` / `.cs` — tray-resident entry point
- `app.manifest` — PerMonitorV2 DPI awareness
- `build.ps1` — one script → portable exe + WiX MSI (+ checksums) in `dist/`
- `installer/ZenTab.wxs` — the WiX MSI definition
- `assets/` — the brand mark (`zentab.svg`) + app icon (`zentab.ico`) + its generator
  (`make-icon.ps1`)
- `docs/review-notes.md` — review backlog (bugs, feel/perf, packaging)

> CI + release workflows live at the repo root in [`../.github/workflows/`](../.github/workflows/)
> (`windows-ci.yml`, `windows-release.yml`), path-scoped to `windows/**`. Cut a release by
> pushing a `windows-v*` tag.

## License

[GPL-3.0](../LICENSE) © Yasin Uslu. Repo-wide, across both platforms.

## Not yet done (next steps)

- **Code signing** — the exe and MSI are unsigned, so SmartScreen warns on first run.
- **Per-monitor-DPI correctness** for panel/thumbnail placement on mixed-DPI multi-monitor.
- **Cross-desktop window curation (Phase 2)** — bring/send windows across virtual desktops,
  and the per-window (not per-app) everyday list, to fully match the macOS scopes. Gated on
  Windows' undocumented Virtual Desktop COM APIs; see the
  [review backlog](docs/review-notes.md).
- More from the [review backlog](docs/review-notes.md) — notably the lone-Alt menu-cue bug
  and background pre-warming of the candidate list.
