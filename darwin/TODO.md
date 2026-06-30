# ZenTab TODO: cross-Space switching (port alt-tab's window engine)

Branch: `cross-space-switchability-wip` (on top of merged main `ae7d185`). Deeper
root-cause notes: `/tmp/zentab-handoff.md` (read if still present). alt-tab clone (GPL,
reference only, do not paste): `~/code/.profile/yasinuslu/github/lwouis/alt-tab-macos`.
Read `VISION.md` and `CLAUDE.md` first.

## Mission
Make the three switcher shortcuts list and switch to the RIGHT windows (including other
Mission Control Spaces) reliably and instantly. ZenTab is a FOCUSED, free re-release of
alt-tab's window engine: port alt-tab's proven solutions, do not reinvent them.

## Principle
Only show entries we can actually act on: a real AX window we can focus, OR a running app
we can activate/reopen. The list must reflect what we can do right now.

## Division of labor (do not violate)
- KEEP ZenTab's shortcut/capture layer: `HotkeyTap` (CGEventTap) + native Cmd+Tab override
  + watchdog/auto-restore (`Input/CaptureWatchdog`, `NativeHotkeyConflict`,
  `NativeHotkeyRestore`, `CaptureHealth`, `App/LaunchProfile`). This reliable shortcut
  grabbing is ZenTab's whole reason to exist (alt-tab's is flaky, ours is solid). Sacred;
  do not destabilize it.
- PORT alt-tab's window engine onto it: enumeration, cross-Space discovery, filtering,
  focus, windowless-app reopen.

## Licensing (DECIDED: GPL-3.0)
The user chose GPL-3.0 (a reliable app he owns and uses; anyone else is welcome). The
GPL-3.0 `LICENSE` is in the repo and the README credits alt-tab-macos / @lwouis. Porting
alt-tab code is therefore cleared (ZenTab is a GPL-3.0 derivative). Optional later: add
SPDX/GPL headers to source files.

## Behavior spec (authoritative, from the user's alt-tab config)
| Mode | Trigger | Apps | Spaces | Screens | Min | Hidden | Fullscreen | No-window apps |
|--|--|--|--|--|--|--|--|--|
| otherApps | Cmd+Tab | All | Visible Spaces | Screen showing switcher | Hide | Hide | Hide | Hide |
| currentApp | Cmd+` | Active app | All Spaces | All screens | Show | Show | Show | Show at end |
| everything | Opt+Tab | All | All Spaces | All screens | Show | Show | Show | Show at end |

- `currentApp` = the ACTIVE app EVERYWHERE (this overrides VISION's current-Space wording;
  update VISION.md).
- Windowless apps appear LAST in `currentApp`/`everything`; selecting one ACTIVATES the app
  so it reopens a window (Chrome with all windows closed spawns a fresh one, like a Dock
  click = `kAEReopenApplication`, not a bare `NSRunningApplication.activate()`).
- These seven filters are FIXED per mode, not user config. Only trigger keys + hold
  threshold are configurable (TOML), per VISION principle 2.

## Current WIP (what is done, what is broken)
- Working: thumbnail cache (live > stale > icon) + 6s background refresh;
  `CGSHWCaptureWindowList` binding (smoke-tested, not yet wired); headless dump via SIGUSR1.
- Half-built and WRONG: everything-mode is now AX-primary (good: phantoms, duplicates, and
  Finder-desktop entries are gone) using brute-force AX discovery
  (`_AXUIElementCreateWithRemoteToken`) to reach other-Space windows (proven to work). BUT
  brute-force runs in the SUMMON hot path, so Option+Tab lags ~1.5s (perf regression), and a
  bounded scan still misses high-id windows of long-lived apps (Chrome, Notes). Fix this.

## Tasks (in order)
1. [DONE] License = GPL-3.0; `LICENSE` added, README credits alt-tab. Porting is cleared.
2. AX window registry + observers (THE fix). Persistent, thread-safe registry
   `[wid -> {AXUIElement, pid, subrole, title, minimized, frame}]`, populated OFF the summon
   path by AXObservers. Per running `.regular` app: `AXObserverCreate` + run-loop source;
   subscribe the app element to WindowCreated / FocusedWindowChanged / MainWindowChanged /
   ApplicationActivated / Hidden / Shown; per created window subscribe UIElementDestroyed.
   Seed each app at startup and on `NSWorkspace.didLaunchApplication` via
   `kAXWindowsAttribute` + `bruteForceAXWindows`. Purge on app terminate. Pack `(pid,wid)`
   into the AXObserver refcon (alt-tab pattern). Port from alt-tab: `AccessibilityEvents.swift`,
   `Applications.swift`/`Application.swift`, `AXUIElement.swift` (`allWindows`,
   `subscribeToNotification`).
3. Repoint `WindowEnumerator.collectEverything` at the registry (instant read); REMOVE
   brute-force from the summon path. Keep CG only for z-order/bounds.
4. Filtering: implement the three mode profiles (apps/spaces/screens/min/hidden/fullscreen/
   windowless) as FIXED behavior. Port `WindowFilterResolver` + the Space/screen helpers.
   Include windowless apps (`isWindowlessApp`) ordered last in `currentApp`/`everything`.
5. Windowless-app select => activate + reopen so a window spawns (find alt-tab's exact
   mechanism; verify Chrome). The entry model must allow an app-only entry (no wid).
6. Cross-Space focus: `WindowFocuser` should use the registry's cached `AXUIElement` for the
   AX raise / de-minimize (`findAXWindow` is current-Space only today). Keep the SLPS front +
   synthetic-click + origin-Space repair sequence.
7. Thumbnails: wire `CGSHWCaptureWindowList` (`hwCapture`) as the fallback for windows SCK's
   on-screen pass misses (off-Space / minimized).

## Verify (no user needed)
```
killall ZenTab 2>/dev/null; sleep 1; rm -f ~/zentab-switchability.txt
env -u LD bin/run >/dev/null 2>&1
for i in $(seq 1 15); do pid=$(pgrep -x ZenTab); [ -n "$pid" ] && break; sleep 1; done
sleep 3; kill -USR1 "$pid"; sleep 2; cat ~/zentab-switchability.txt; killall ZenTab
```
Rows with `AX` = real AX windows the new enumeration shows. Expect MANY more AX rows after
the registry lands, and instant summon. (The dump's SHOWN/hide column is the OLD probe
union, not the new `collectEverything`; judge by the `AX` rows.) Then hand to the user for
`bin/run-prod`. AX permission is already granted (current-Space windows always have AX; this
was never a TCC issue). The user has NO external monitor now, so CG geometry is wonky; do not
over-fit to that state.

## Constraints
Do not touch the shortcut/capture layer. Resource hygiene: observers are event-driven (good);
NO polling-all-apps timers; kill any dev ZenTab you launch. No em dashes in prose. Concise and
decisive. Commit/push only when the user says so. New `.swift` files need `bin/generate`. App
Sandbox is OFF; private SPIs via `@_silgen_name` in `ZenTab/Private` (smoke-test new ones).

## Key files
`Window/WindowEnumerator.swift` (`collectEverything`, `axDetails(for:bruteForce:)`,
`bruteForceAXWindows`, the `SwitchabilityProbe` dump), `Window/WindowFocuser.swift`,
`Window/WindowInfo.swift` (`isSwitchable`), `Private/HIServicesSPI.swift`
(`_AXUIElementGetWindow`, `_AXUIElementCreateWithRemoteToken`), `Private/SkyLight.swift`
(SLPS/CGS + `CGSHWCaptureWindowList`), `App/AppModel.swift` (`bootstrap` starts the tracker;
dump), `Overlay/OverlayController.swift`, `Switcher/OverlaySession.swift` (pure reducer, do
not disturb).
