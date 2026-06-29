# ZenTab

An opinionated Alt-Tab alternative for Windows. C# + WPF on .NET 10, with a thin
Win32/DWM interop layer (`Native.cs`). Read [VISION.md](VISION.md) first — ZenTab is
about *feel and performance*, not configurability.

## Current state

ZenTab is resident in the tray (no main window) and **replaces the native switching
gestures** via a low-level keyboard hook:

| Gesture | Shows | Scope |
| --- | --- | --- |
| **Alt + Tab** | apps — one entry per app | current monitor + current desktop |
| **Alt + `** | windows of the current app | current desktop, all monitors |
| **Ctrl + Alt + Tab** | everything (the "I lost something" escape hatch) | all monitors, all desktops |

- **Hold to cycle, release to commit.** Tab / `→` advance, Shift+Tab / `←` reverse;
  releasing the modifier switches to the selected window.
- **Mouse hover selects too** — move the mouse over a card to select it, then release to
  switch (or click to switch immediately). Keyboard and mouse share one selection; last
  input wins.
- **Live DWM thumbnails** of each window, in a floating panel on the **monitor under the
  cursor**. "Current monitor" = wherever the mouse is.
- Initial selection is the **MRU-previous** entry, so a blind quick-tap toggles between
  two apps even though the list is in **stable order** (by first-seen).
- **Minimized windows are excluded** entirely (use the taskbar to restore).
- In-overlay actions: **Delete** closes the selected window, **Shift+Delete** quits the app.
- **Esc** dismisses without switching.
- The world **dims** behind the panel (a translucent, see-through layer) and the cards
  **fade in** (~100 ms).

Quit from the tray icon's right-click menu.

## Develop on the terminal

```powershell
dotnet run            # run it
dotnet watch run      # hot-reload loop (or ./dev.ps1)
dotnet build          # build only
dotnet publish -c Release   # -> bin/Release/net10.0-windows/
```

### Dev mode — test without hijacking the real Alt+Tab

Editing global Alt+Tab while you work is risky. `zentab.toml` has a **developer-only**
toggle (not user-facing config — ZenTab is intentionally not configurable) that swaps in
alternate shortcuts so your normal Windows keybindings keep working. **It ships enabled**
while we develop:

```toml
[dev]
enabled = true          # set false to use the real Alt+Tab / Alt+` / Ctrl+Alt+Tab
modifier = "ctrl+alt"   # held modifier — release to commit
apps        = "Tab"     # like Alt+Tab
app_windows = "`"       # like Alt+`
everything  = "F1"      # like Ctrl+Alt+Tab
```

With this, hold **Ctrl+Alt**, tap **Tab** to summon apps and keep tapping to cycle
(**Shift+Tab** to go back), or move the **mouse** over a card — then release Ctrl+Alt to
switch. The active scheme is shown in the tray tooltip and menu.

## Layout

- `Native.cs` — all Win32/DWM P/Invoke (enumeration, hooks, monitors, icons, thumbnails, activation)
- `WindowService.cs` — warm window state: stable order, MRU, per-mode scoping, entry build
- `KeyboardHook.cs` — low-level hook + gesture detection (fast callback, work deferred)
- `OverlayWindow.xaml` / `.cs` — the floating card panel (thumbnails, fade, hover, commit)
- `DimWindow.cs` — the translucent recede layer behind the panel
- `SwitcherController.cs` — glues hook + window state + overlay together
- `Config.cs` / `zentab.toml` — dev-mode shortcut profile
- `App.xaml` / `.cs` — tray-resident entry point

## Not yet done (next steps)

- **GPU blur** on the dim layer (currently a flat translucent dim, no blur).
- Per-monitor-DPI correctness for the panel/thumbnail placement on mixed-DPI multi-monitor
  setups (works on uniform DPI).
