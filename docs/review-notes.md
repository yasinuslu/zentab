# Review notes

Findings from a round of fresh-eyes reviews (3 independent reviewers: a bug hunter, a
feel/performance reviewer against [VISION.md](../VISION.md), and a packaging/release
reviewer). This is a working backlog, not a contract — items are notes to act on, prune,
or reject as the vision dictates.

Status legend: ⬜ open · ✅ addressed in this pass · 🔭 deliberate / vision call.

---

## Correctness bugs

- ✅ **Phantom system windows shown (e.g. "Windows Input Experience"/TextInputHost).**
  `IsCandidate` now drops the UWP shell `Windows.UI.Core.CoreWindow` (TextInputHost,
  SearchHost, ShellExperienceHost, …) and `Progman`/`WorkerW` — mode-independently, since
  Everything mode keeps shell-cloaked windows. Also adopted Raymond Chen's
  GA_ROOTOWNER/GetLastActivePopup owner-walk and the `WS_EX_APPWINDOW` tool-window override.
  Verified on live windows: phantom dropped, real apps (incl. UWP `ApplicationFrameWindow`)
  kept. Deliberately did NOT use `WS_EX_NOREDIRECTIONBITMAP` (real apps here set it).
- ⬜ **HIGH — Lone-Alt menu activation.** `KeyboardHook.cs:84,111,125` swallows only the
  trigger key, never the modifier, so a full Alt+Tab cycle looks to the OS like Alt
  pressed+released with no intervening key → can leave the newly-focused window in
  keyboard-menu-cue mode (`SC_KEYMENU`). Classic hook-based Alt+Tab defect; hurts the
  "calm, invisible" feel. Needs a runtime repro, then likely inject a no-op key or handle
  `WM_SYSKEYUP` so the menu cue never triggers.
- ⬜ **MEDIUM — Unbounded dictionary growth + HWND reuse.** `WindowService.cs:21-26,69-80`
  only ever adds to `_firstSeen` / `_lastActive` (hooks `EVENT_SYSTEM_FOREGROUND` but not
  `EVENT_OBJECT_DESTROY`). All-day residency → working-set creep (contradicts near-zero
  idle), and recycled HWNDs inherit a stale window's stable position + MRU, corrupting the
  two core ordering features. Prune on destroy or when `IsWindow` fails during `Build`.
- ⬜ **MEDIUM — `GetMonitorInfo` return value ignored.** `Native.cs:125-130`
  (`CursorMonitorWorkArea`). On a stale monitor handle (unplug / resolution change) `rcWork`
  stays zero and the overlay places near (0,0) with bad geometry. Check the BOOL and fall
  back gracefully.
- ⬜ **LOW — Armed second-gesture ignores its mode.** `SwitcherController.cs:68-74`: arming
  one mode then firing a different trigger before the reveal shows the first mode's entries.
- ⬜ **LOW — Keystrokes leak to the app while the overlay is up.** `KeyboardHook.cs:111`:
  non-navigation keys return `false` and reach the still-foreground app (overlay is
  `WS_EX_NOACTIVATE`), so typing edits the document behind the switcher.
- ⬜ **LOW — `Post` during dispatcher shutdown.** `KeyboardHook.cs:160` `BeginInvoke` can
  throw across the native→managed boundary in the shutdown window before unhook.
- ⬜ **LOW — Panel max-size keyed to primary screen.** `OverlayWindow.xaml.cs:44-45` uses
  `PrimaryScreen*` but centers on the cursor monitor; a crowded list can overflow a smaller
  secondary monitor.
- ⬜ **LOW — "Stable order" isn't launch order on first summon.** `WindowService.cs:52-67`:
  `Warmup` fills only the path caches, not `_firstSeen`, so the first summon seeds all
  pre-existing windows in `EnumWindows` (≈z-order) order, not launch order.

_Reviewer confirmed clean:_ threading model (single-threaded via dispatcher), x64 P/Invoke
signatures, hook/event-hook uninstall, DWM thumbnail register/unregister balance,
re-summon-during-fade guards.

## Feel & performance (vs VISION.md)

- 🔭 **No blur — the recede is a flat dim.** `DimWindow.cs:28` flat translucent color;
  `OverlayWindow.xaml:6` opaque panel. VISION wants a GPU-backed acrylic/composition blur.
  Biggest gap vs the stated visual identity. (Already on the README roadmap as "GPU blur".)
- ⬜ **Dim is a software-composited full-virtual-screen layered window.** `DimWindow.cs`
  uses `AllowsTransparency=true` (WPF software layer) sized to all monitors, animating
  `Opacity` per frame — the CPU per-frame path VISION warns against; worst on the
  multi-monitor setups this targets. Move the backdrop to a DWM/composition surface.
- ⬜ **Hook shares the UI thread that does heavy summon work.** Enumeration, WPF layout, and
  `DwmRegisterThumbnail` run on the same thread as the `WH_KEYBOARD_LL` callback, so
  subsequent keystrokes can stall behind summon work (and Windows can silently drop a slow
  hook past `LowLevelHooksTimeout`). Consider a dedicated hook thread with its own pump.
- ⬜ **Enumeration is cold on the gesture.** `WindowService.Warmup` warms only path caches;
  the candidate list (`EnumWindows` + cloak/monitor/pid P/Invokes + grouping/sort) is built
  fresh every summon. Maintain a live candidate set in the background.
- ⬜ **Quick tap pays full enumeration it doesn't need.** `SwitcherController.cs:112` reaches
  the MRU-previous target only after a full `Build`; the target is derivable from
  `_lastActive` alone. Make blind tap-toggle enumerate nothing.
- 🔭 **200 ms hold before the fade begins.** `SwitcherController.cs:17`. Tension with "begin
  the fade the moment the shortcut fires"; quick-tap invisibility forces *some* delay.
  Consider gating quick-tap on "mouse not yet moved" (per spec wording) over a fixed timer.
- ⬜ **Thumbnails register after the fade starts.** `OverlayWindow.xaml.cs:91-93` queues
  `PlaceThumbnails` at `Loaded`, so cards fade in empty then fill. Register before/at the
  first frame, or stagger.
- ⬜ **Per-summon allocation churn.** Fresh `List`, `EnumWindowsProc` delegate, and
  `StringBuilder`s per enumeration (`Native.cs:271-276`) + LINQ in `Build` — an allocation
  spike right when the fade starts. Cache the delegate / reuse buffers.
- 🔭 **Mixed-DPI multi-monitor positioning.** `OverlayWindow.xaml.cs:166-167` assumes uniform
  DPI (acknowledged). _Partially mitigated this pass: added a PerMonitorV2 app.manifest._

_Reviewer confirmed faithful:_ lean hook callback, win-event-driven MRU, no idle polling,
fades within the 80–120 ms spec. Philosophy check: the dev-only `zentab.toml` is a build/test
seam, not a configurability leak.

## Packaging & release

- ✅ **build.ps1 didn't check native exit codes / could package a stale exe.** Now sets
  `$PSNativeCommandUseErrorActionPreference`, cleans the publish dir before publishing, and
  verifies both artifacts exist.
- ✅ **WiX v5 pin not enforced when wix is on PATH.** Now validates `wix --version` is 5.x and
  fails with a clear message otherwise.
- ✅ **Version not single-sourced.** `build.ps1 -Version` flows into the exe, MSI, wxs, and
  filenames; CI derives it from the git tag; version string is validated MSI-legal.
- ✅ **No application icon (exe / ARP / shortcut all generic).** Added placeholder
  `assets/zentab.ico` (+ generator), `ApplicationIcon`, embedded for the tray, and
  `ARPPRODUCTICON` + shortcut icon in the MSI.
- ✅ **No CI / tag-based release.** Added `.github/workflows/ci.yml` and `release.yml`
  (tag `v*` → build + checksums → GitHub Release).
- ✅ **No SDK pin.** Added `global.json`.
- ✅ **Portable "no dev toml" guarantee was incidental.** Made explicit with
  `CopyToPublishDirectory="Never"`.
- ✅ **Safe size trims.** `InvariantGlobalization` + `SatelliteResourceLanguages=en` (~72→66 MB).
- ✅ **No app.manifest / DPI awareness.** Added PerMonitorV2 manifest.
- ✅ **MSI reinstall of same version.** Added `AllowSameVersionUpgrades="yes"`.
- ✅ **No checksums.** `build.ps1` now emits `dist/SHA256SUMS.txt`; release attaches it.
- ⬜ **No code signing.** Unsigned MSI + autostart + global keyboard hook = SmartScreen/AV
  friction. Add Authenticode signing (exe before MSI embed); long-term an EV/Trusted-Signing
  cert. Top remaining release blocker.
- 🔭 **Per-machine vs per-user install.** Per-machine forces UAC and a machine-wide autostart;
  a single-user tray utility is arguably a better per-user fit. Deliberate choice — document why.
- 🔭 **EnableCompressionInSingleFile vs ReadyToRun.** Compression shrinks the file but adds
  first-launch self-extract; R2R trades size for faster cold start. Weigh against the perf pillar.
- ⬜ **Launch-after-install.** MSI only registers autostart (next login); consider a "launch now"
  finish action.
- 🔭 **Full IL trimming / AOT.** Unsupported for WPF — do not attempt. ~66 MB is near the floor.
- ✅ **build.ps1 requires pwsh 7.** Added `#requires -Version 7.0`.

## UI / visual (overlay)

From a fresh visual-only review (UX/behavior explicitly out of scope). Palette is Catppuccin
Mocha.

- ✅ **App icon beside the title** (the requested feature). 18px, inline-left, centered as a
  group with the title `MaxWidth`-bounded so it still ellipsizes; the `Image` collapses when
  there's no icon. Icons are extracted from the exe and cached/warmed by path
  (`WindowService`), frozen so they cross the warm-up→UI thread boundary.
- ✅ **Unstyled system scrollbar** → minimal track-less rounded thumb (`CalmScrollBar` in
  `App.xaml`), applied to the list.
- ✅ **Square window corners / no elevation** → `DwmSetWindowAttribute` round corners in
  `OverlayWindow.OnSourceInitialized`, which also restores the native soft shadow.
- ✅ **Misleading thumbnail corner radius** → removed (DWM thumbnails are square; honest now).
- ✅ **Faint selection** → unselected titles muted (Subtext0), selected title brightened
  (Text), keeping the existing wash/border. No motion (keeps "last input wins" snappy).
- ✅ **White-tinted letterbox bars** → neutral dark placeholder (Mantle).
- ✅ **Empty state** → a deliberate muted "Nothing here" at a sensible min panel size.
- ✅ **No shared palette + `#1E1E2D` typo** → palette centralized as brushes in `App.xaml`;
  Base corrected to `#1E1E2E`.
- ⬜ **Ragged last wrap row.** `WrapPanel` left-aligns a partial final row under a centered
  window. Deferred — true centered-wrap needs a custom panel; low value.
- 🔭 **GPU blur backdrop** (also a feel/perf item above) remains the big visual TODO; the
  recede is still a flat dim.
