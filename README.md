# ZenTab

**An opinionated Alt+Tab alternative for Windows.** C# + WPF on .NET 10, with a thin
Win32/DWM interop layer.

> ZenTab is not about its interface — it's about the **feel**, and the **focus** it brings.
> The whole focus is two co-equal pillars: **feel and performance**. It is *very*
> opinionated: for each choice we pick one behavior and delete the knob. See
> [VISION.md](VISION.md).

ZenTab is resident in the tray (no main window) and **replaces the native switching
gestures** with a low-level keyboard hook.

## What it does

| Gesture | Shows | Scope |
| --- | --- | --- |
| **Alt + Tab** | apps — one entry per app | monitor under the cursor |
| **Alt + `** | windows of the current app | current desktop, all monitors |
| **Ctrl + Alt + Tab** | everything — the "I lost something" escape hatch | all monitors, all desktops |

- **Quick tap = instant switch.** Tap and release within ~200 ms and ZenTab switches
  straight to your previous window — the overlay never even appears (just like native
  Alt+Tab). Hold past the threshold, or tap again, to reveal the switcher.
- **Hold to cycle, release to commit.** Tab / `→` advance, Shift+Tab / `←` reverse;
  releasing the modifier switches to the selected window.
- **Mouse hover selects too.** Move over a card to select it, then release to switch (or
  click to switch immediately). Keyboard and mouse share one selection; last input wins.
- **Live DWM thumbnails** in a floating panel on the **monitor under the cursor**, over a
  translucent dim so the rest of the world recedes.
- **Stable order** (by first-seen) so you build muscle memory; initial selection is the
  **MRU-previous** entry so blind tap-toggling between two apps works.
- **Minimized windows are excluded** (use the taskbar to restore them).
- In-overlay actions: **Delete** closes the selected window, **Shift+Delete** quits the
  app, **Esc** dismisses.

Performance is a feature: window state is pre-warmed in the background, so a warm summon
costs well under a millisecond; the keyboard hook does only cheap work on the input path;
idle cost is near zero (one foreground event hook, no polling).

## Install

Download / build the MSI and run it. It installs ZenTab to *Program Files*, adds a Start
Menu shortcut, and starts ZenTab at login. Quit anytime from the tray icon's menu.

```powershell
./build-installer.ps1        # -> dist/ZenTab-0.1.0-win-x64.msi
```

The installer bundles a **self-contained** build, so .NET does not need to be installed on
the target machine. The installed app uses the real Alt+Tab / Alt+` / Ctrl+Alt+Tab
gestures.

> Heads-up: this is an early build (0.1.0). The MSI is unsigned, so SmartScreen may warn
> on first run.

## Build & run from source

```powershell
dotnet run            # run it (framework-dependent, fast inner loop)
dotnet watch run      # hot-reload loop (or ./dev.ps1)
dotnet build          # build only
dotnet publish -c Release -r win-x64   # self-contained single-file exe -> bin/Release/.../publish
```

### Dev mode — test without hijacking the real Alt+Tab

Rebinding global Alt+Tab while you work is risky. `zentab.toml` has a **developer-only**
toggle (not user-facing config — ZenTab is intentionally not configurable) that swaps in
alternate shortcuts so your normal Windows keybindings keep working. **It ships enabled in
the source tree:**

```toml
[dev]
enabled = true          # set false to use the real Alt+Tab / Alt+` / Ctrl+Alt+Tab
modifier = "ctrl+alt"   # held modifier — release to commit
apps        = "Tab"     # like Alt+Tab
app_windows = "`"       # like Alt+`
everything  = "F1"      # like Ctrl+Alt+Tab
```

Hold **Ctrl+Alt**, tap **Tab** to cycle apps (**Shift+Tab** to go back), or use the
**mouse** — then release Ctrl+Alt to switch. The active scheme is shown in the tray
tooltip and menu. `zentab.toml` is build-tree-only; the MSI does not ship it.

## How it works

- `Native.cs` — Win32/DWM P/Invoke (enumeration, hooks, monitors, thumbnails, activation)
- `WindowService.cs` — warm window state: stable order, MRU, per-mode scoping, entry build
- `KeyboardHook.cs` — low-level keyboard hook + gesture detection (lean callback)
- `SwitcherController.cs` — orchestration, including the quick-tap threshold
- `OverlayWindow.xaml` / `.cs` — the floating card panel with live thumbnails
- `DimWindow.cs` — the translucent recede layer behind the panel
- `Config.cs` / `zentab.toml` — dev-mode shortcut profile
- `App.xaml` / `.cs` — tray-resident entry point
- `installer/ZenTab.wxs` + `build-installer.ps1` — the WiX MSI

## Not yet done (next steps)

- **GPU blur** on the dim layer (currently a flat translucent dim).
- Per-monitor-DPI correctness for panel/thumbnail placement on mixed-DPI multi-monitor.
- A signed installer + a real app icon.
