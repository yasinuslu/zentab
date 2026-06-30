# Cross-Space move: feasibility spike + autonomous proof loop

Status: **EXECUTED — GREEN (macOS 26.5.1).** Another app's window can be moved across
Mission Control Spaces from a normal process, App Sandbox off, **no SIP**, with
**single-window precision**. See "Result" below; the gated feature is `docs/window-curation.md`.

## Result (2026-06-30, macOS 26.5.1, Apple Silicon)

**Winner: the modern bridged window-management operation.** Build an
`SLSBridgedMoveWindowsToManagedSpaceOperation` through the ObjC runtime
(`initWithWindows:spaceID:`) and perform it with its zero-argument
`performWithWMBridgeDelegate` method. Both directions verified (current Space to another
Space and back), clean (no forced Space switch), confirmed against the WindowServer's own
per-Space composited list (`SLSCopyWindowsWithOptionsAndTags`). A two-window helper proved
it moves **only the target window**; the app's other windows stay put. No persistent
process assignment. This is yabai's macOS >= 15 path; yabai reaches the dispatcher via a
hidden local C symbol it Mach-O-scans for, but the operation object's
`performWithWMBridgeDelegate` is directly callable through the ObjC runtime, so no Mach-O
scan is needed.

**Also works, but not chosen:** `SLSProcessAssignToSpace(cid, pid, sid)` (and
`SLSProcessAssignToAllSpaces` + assign) move the window without SIP, but at **process
granularity** (all of an app's windows) and behave like the Dock's "Assign To" binding.
Kept only as a coarse fallback.

**Confirmed inert on macOS 26 (do not use):** every window-targeted CGS/SLS call,
`CGSMoveWindowsToManagedSpace` and its `SLS` twin, the
`CGSAddWindowsToSpaces`/`CGSRemoveWindowsFromSpaces` pair,
`CGSSpaceAddWindowsAndRemoveFromSpaces`, `CGSMoveWorkspaceWindowList`, and yabai's
compat-id dance (`SLSSpaceSetCompatID` + `SLSSetWindowListWorkspace`). They return without
error and the window does not move.

**Harness (left in the working tree, dev-only, not wired into the app):**
`ZenTab/Spike/SpaceMoveSpike.swift` (helper + oracle + 11-strategy ladder + precision
test), the `--space-move-helper` / `--space-move-selftest` launch args dispatched in
`ZenTab/App/Main.swift`, the bindings in `ZenTab/Private/SkyLight.swift`, and
`bin/space-move-test` (build, run headless, print the table, exit 0/1/2). Re-run any time
with `bin/space-move-test`. Requires >= 2 Desktops on the main display.

---

The original plan follows, for context.

Status (original): **planned, not executed.** This is a self-contained handoff. A fresh
session picks it up, runs the loop, and reports GREEN (with the winning strategy) or RED
(with a clean negative). Read `docs/window-curation.md` (the feature this gates),
`VISION.md`, and `CLAUDE.md` first.

## The one question to settle

Can ZenTab move **another app's window** to a different Mission Control Space on **macOS
26**, from a normal process, **without SIP**? Everything in `window-curation.md` (summon =
bring here, fling = send away) rests on this. yabai needs a SIP-disabled scripting
addition for it; alt-tab never shipped it and flagged the APIs "unreliable"; one sibling
call died after macOS 12.2. So it is genuinely unknown and must be **proven by test, not
argued.** Honest prior: ~60-65% for "bring to current Space," lower for arbitrary Spaces.

## The approach (two pillars)

1. **A reliable, repeatable, headless oracle** that gives a hard pass/fail for "did the
   window actually change Space." No human eyeballing.
2. **A ladder of move strategies.** The loop runs the oracle against each strategy until
   one passes (GREEN, record which) or all fail (RED, pivot to monitor-only).

The oracle is the fitness function; the ladder is the search space; the loop is "work
yourself out until you achieve it."

## Pillar 1: the oracle (reliable test)

Design goals: deterministic target, tests the real case (another process's window), tests
**both directions**, verifies programmatically, restores cleanly, needs no human at the
keyboard, never creates a Space.

**Controlled target = a second process.** Not a random user window (those vary run to
run, some report multiple/sticky Spaces). Launch a throwaway window from a separate PID so
it is genuinely "another app" with its own WindowServer connection, the privilege case we
must test. Simplest: re-exec the ZenTab binary with `--space-move-helper` (separate PID +
connection, no new target). The helper sets `.regular` activation, opens one plain
standard window, prints its `CGWindowID` to stdout, and idles until killed.

**Procedure (one self-test run):**
1. Launch the helper. Read its `wid`. Its window opens on the current Space `S1`.
2. Enumerate Spaces on the main display via `CGSCopyManagedDisplaySpaces`; pick any
   `S2 != S1`. **Precondition:** ≥2 Desktops exist. If only one, SKIP with a clear message
   (the human creates a second Desktop once; we never create one in code).
3. **Fling direction:** move `wid` `S1 → S2` with the strategy under test. Poll
   `CGSCopySpacesForWindows(wid)` up to ~800 ms (WindowServer is async). Assert it now
   contains `S2`.
4. **Summon direction:** move `wid` `S2 → S1`. Poll, assert it now contains `S1`.
5. Quit the helper.
6. **PASS** iff both 3 and 4 verified. Record the strategy, timings, and whether the
   user's current Space stayed `S1` throughout (clean) or the move forced a Space switch
   (degraded pass, note it).

This needs no pre-placement and no Space switching: the helper opens on `S1`, we push it
away and pull it back. The oracle reads Space **ids**, not pixels, so it is robust to the
window being off-screen between steps.

## Pillar 2: the strategy ladder

Each entry is one move implementation; the self-test runs them in order, restoring between
each. First to pass both directions wins.

1. `CGSMoveWindowsToManagedSpace(cid, [wid], dest)` — single call. *(binding added)*
2. `CGSAddWindowsToSpaces(cid, [wid], [dest])` + `CGSRemoveWindowsFromSpaces(cid, [wid],
   [origin])` — the pair. *(bindings added)*
3. Strategy 1, but **front/raise the target first** (`_SLPSSetFrontProcessWithOptions` +
   the existing key sequence) in case the WS only honors moves on the active window.
4. Strategy 1 wrapped in a `CGSManagedDisplaySetCurrentSpace` dance (switch to dest, move,
   switch back) — degraded if it works, but informative. *(binding to add)*
5. `CGSSpaceAddWindowsAndRemoveFromSpaces(cid, dest, [wid], 0x80007)` — alt-tab's
   experimental call, annotated 10.10-12.2; try anyway on 26. *(binding to add)*
6. `CGSMoveWorkspaceWindowList(cid, [wid], 1, dest)` — alt-tab experimental. *(binding to add)*

Signatures live in the alt-tab reference (`src/experimentations/PrivateApis.swift`,
`src/macos/api-wrappers/SkyLight.framework.swift`). Read for the symbol/ABI, do not paste.

## How it runs (headless)

- **Self-test entry in the app:** a launch arg `--space-move-selftest` runs the *whole
  ladder* in one process and writes a result table to `~/zentab-spacemove.txt` plus an
  exit code (0 = some strategy GREEN, 1 = all RED, 2 = SKIPPED/precondition). `--space-move-helper`
  is the child-window mode above. Both are dev-only entry points; they must not perturb the
  shortcut/capture layer (guard them so the normal menu-bar app path is untouched).
- **Wrapper `bin/space-move-test`:** `env -u LD` build, launch `--space-move-selftest`,
  wait for the result file, `killall` the app + any helper, print the table and exit code.
- **The loop (the agent):** code the ladder → build once → run `bin/space-move-test` →
  read the table. If GREEN, stop and record the winner. If a strategy is a near miss
  (moves one direction, or moves-but-switches), tweak flags/ordering, rebuild, rerun. If
  the ladder is exhausted with no green, stop: the answer is RED. **Bounded loop** — at
  most the ladder plus a few tweak iterations; never spin.

## Success criteria

- **GREEN:** ≥1 strategy moves the helper **both directions**, verified, ideally without
  forcing a Space switch. Deliverable: the winning strategy + flags + observed side
  effects, and update `window-curation.md` feasibility from "unproven" to "proven via
  `<strategy>` on macOS 26." Summon/fling are unblocked.
- **RED:** the whole ladder fails. That is a real, valuable result, not a failure of the
  work. Deliverable: the negative documented, and `window-curation.md` pivoted to
  **monitor-move only** (reliable AX-frame reposition, no private Space APIs); summon and
  fling-to-Space shelved.

## Files and bindings

- **Already added** (`ZenTab/Private/SkyLight.swift`): `CGSMoveWindowsToManagedSpace`,
  `CGSAddWindowsToSpaces`, `CGSRemoveWindowsFromSpaces`.
- **To add (execution session):** `CGSCopyManagedDisplaySpaces` (enumerate Spaces for the
  oracle); ladder bindings 4-6 as reached; the `--space-move-helper` / `--space-move-selftest`
  entry points (new `.swift` under `ZenTab/`, then `bin/generate`); `bin/space-move-test`.
- **Reference (read, never copy — GPL):** `~/code/.profile/yasinuslu/github/lwouis/alt-tab-macos`.

## Hard rules (hygiene, from the project + Yasin's standing prefs)

- **No orphans.** `killall` the helper and any dev ZenTab after every run; watch CPU and
  process count. Never leave a build or app running between iterations.
- `env -u LD` before any `xcodebuild` (his shell's `LD=ld` breaks CLI linking).
- New `.swift` files need `bin/generate`; never hand-edit the `.pbxproj`.
- **Do not touch** the shortcut/capture layer (`HotkeyTap`, watchdog, native-hotkey
  override). The self-test must not disable any symbolic hotkey.
- App Sandbox stays OFF; **SIP stays ON** (if a strategy "works" only with SIP off, it does
  not count — that violates the product principles).
- Bounded loop, no leftover timers. **Do not commit** until Yasin says so.

## Human preconditions (one-time, before the execution session runs)

- **≥2 Desktops on the main display** (System Settings or Mission Control: add a Desktop).
  The oracle needs a second Space to move into; it will not create one.
- Accessibility already granted to ZenTab. Screen Recording optional (not needed for the
  Space-id oracle).
- Run on a real login session (the WindowServer is unavailable over plain SSH).
