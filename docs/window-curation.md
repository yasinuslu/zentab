# Window curation: summon and fling

Status: **design, from an interview.** Not built. The cross-Space half rests on a
private API that is unproven on macOS 26 (see "The wall" and "Build order"). Reviewed
shape below; confirm the marked decisions before building.

## The idea

A switcher answers "where is my window?" Curation answers the opposite: "bring my
windows to me, and push the ones I don't want away." Two verbs, layered onto the
existing held overlay next to `W`=close / `Q`=quit:

- **Summon (bring here):** with a window highlighted, press **Space**. It moves to your
  current Space. The tile flies down into the here-strip (below).
- **Fling (send away):** with a window highlighted, press an **arrow**. It moves to an
  adjacent Space (`←` / `→`), or with **Ctrl** to another monitor (`Ctrl+←/→`, and
  `Ctrl+↑/↓` for stacked displays). The tile flies off that edge. **You stay put.**

The signature workflow: open an empty Space, stand in it, `Option+Tab`, and pull in
exactly the windows you want for this moment. Curation by gathering, not hunting.

## Why "bring here" is the smart primitive

The first instinct was the send-away fling to an arbitrary Space, and at the last Space,
*create* a new one. Creating a Space from a normal app connection is the part that
historically needs Dock-injection with SIP partially disabled (yabai's path), which
ZenTab forbids. A Space made any other way tends to be an orphan Mission Control won't
show correctly.

Summon dodges that entirely: its destination is always **the current, active Space.**
No Space-creation, no destination-picking. It is the single cross-Space move most likely
to actually survive on macOS 26, because the active Space is real and present. Same
private call as fling under the hood, just aimed at the current Space id. So summon is
the first thing to prove; if it works, the whole board is unlocked.

## The Option+Tab curation board

`Option+Tab` (the "everything" mode) becomes a two-zone board:

```
┌───────────────────────────────────────────────┐
│   ELSEWHERE  (big grid: windows NOT on this Space)
│   [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ]       │
│   [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ]       │
│                                                 │
│  ───────────────────────────────────────────   │
│   HERE  (small strip: windows on this Space)    │
│   [▓▓] [  ] [  ]                                │
└───────────────────────────────────────────────┘
   Space = pull a grid tile DOWN into the strip
   arrows = push a strip tile UP and out to another Space/monitor
```

- **Partition, no duplication.** The big grid shows only windows **not** here; the strip
  shows the windows that **are** here. Together they are still "everything" (the
  `Option+Tab` promise), just zoned as *there* (top) vs *here* (bottom). A window is
  never shown twice.
- **The strip is free.** "Windows here" is exactly the `Cmd+Tab` set, so the strip is the
  same data shown as a sub-strip. No new enumeration.
- **Both zones are interactive.** Select in either; act in either. Summoning a grid tile
  moves it into the strip (and out of the grid), so the grid selection naturally advances
  to the next elsewhere-window: rapid `Space`-`Space`-`Space` gathers a set for free.
  Flinging a strip tile moves it back into the grid, symmetric.
- **You never follow.** The overlay stays up while the modifier is held so you curate a
  whole set; release focuses the selected window as usual (release is never a cancel).

## Key map (while the overlay is held)

| Key | Action |
| --- | --- |
| `Tab` / `Shift+Tab` | Move selection within the current zone (existing) |
| `↑` / `↓` | Move selection between the grid (up) and the here-strip (down) |
| `Space` | Summon: bring the highlighted window to this Space |
| `←` / `→` | Fling: send the highlighted window to the adjacent Space |
| `Ctrl+←/→`, `Ctrl+↑/↓` | Fling: send the highlighted window to the next monitor |
| `W` / `Q` | Close window / quit app (existing) |
| release | Focus the selected window (existing) |

Geometry is the mnemonic: Spaces extend left/right, so `←/→` flings across them; the
strip sits at the bottom, so `↓` drops into it. `Tab` still does all within-zone
navigation, which is why plain arrows are free to be actions (ZenTab already navigates
with `Tab`, not arrows).

## Feedback

No toasts. The tile's motion is the receipt:

- **Summon:** the tile flies **down into the strip** from its place in the grid.
- **Fling:** the tile flies **off the target edge** (left/right for a Space, up/down/side
  for a monitor) and out of the strip.

Direction tells you what happened and roughly where it went, with zero persistent UI.

## The wall (feasibility): PROVEN on macOS 26, no SIP

Status: **proven** by the spike (`docs/space-move-spike-plan.md`, run on macOS 26.5.1),
the cross-Space half is unblocked. The winning call is the modern **bridged window
management operation**, and it gives true single-window precision without SIP:

- **Winner (use this for summon/fling):** build an
  `SLSBridgedMoveWindowsToManagedSpaceOperation` via the ObjC runtime
  (`initWithWindows:spaceID:`) and perform it in-process with its zero-argument
  `performWithWMBridgeDelegate` method. App Sandbox off, **no SIP**, no persistent process
  assignment. Verified moving a window both directions (current Space to another and back),
  with no forced Space switch, confirmed against the WindowServer's own per-Space composited
  list (`SLSCopyWindowsWithOptionsAndTags`, the list Mission Control renders). A two-window
  helper confirmed it moves **exactly the target window** and leaves the app's other windows
  put. This is the same path yabai uses on macOS >= 15; yabai reaches it through a hidden
  local C dispatcher it Mach-O-scans for, but the operation object's `performWithWMBridgeDelegate`
  method is reachable directly through the ObjC runtime, so no symbol scanning is needed.
- **All the window-targeted CGS/SLS calls are inert on macOS 26.** Tested and confirmed
  no-ops from a normal connection: `CGSMoveWindowsToManagedSpace` / its `SLS` twin, the
  `CGSAddWindowsToSpaces` + `CGSRemoveWindowsFromSpaces` pair, `CGSSpaceAddWindowsAndRemoveFromSpaces`,
  `CGSMoveWorkspaceWindowList`, and yabai's compat-id dance (`SLSSpaceSetCompatID` +
  `SLSSetWindowListWorkspace`). This matches alt-tab's "unreliable" warning; do not rely on them.
- **Process-level fallback:** `SLSProcessAssignToSpace(cid, pid, sid)` works without SIP but
  moves **all** of an app's windows at once and behaves like the Dock's "Assign To" (likely a
  persistent binding). Not used for per-window summon/fling; noted only as a coarse fallback.
- **Creating a Space is still dropped.** Fling sends only to **Spaces that already exist**: if
  there is an adjacent Space, the window goes there; if not, the fling is simply a no-op. No
  Space is ever created (that is the part that would need the SIP/Dock-injection ZenTab refuses).

Moving to another **monitor** has none of this risk: it is just repositioning the window's
AX frame onto the other display. Reliable, no exotic API.

## Build order

1. **Spike the move first** ✅ **DONE, GREEN.** The oracle + ladder proved per-window
   cross-Space moves on macOS 26 via the bridged operation (see "The wall" above and
   `docs/space-move-spike-plan.md`). Summon and fling-to-Space are unblocked. The proven
   move call belongs in a small `SpaceMover` once the UI work begins.
2. **Monitor-move** (reliable) and the **strip UI** (free data) can land in parallel with
   the spike.
3. Wire **summon** (`Space` to current Space) once the spike is green.
4. Wire **fling-to-Space** (`←/→`) on the same proven call.
5. Animations (fly-down / fly-off), then make the strip fully interactive.

## Decisions to confirm

- The board (grid = elsewhere, strip = here) applies to the multi-Space modes:
  `Option+Tab` and **probably `Cmd+\``** (gather a single app's scattered windows to you).
  `Cmd+Tab` is current-Space only, so it stays a flat list with no strip; summon is a
  no-op there, fling still works. **Confirm Cmd+` gets the board.**
- `Space` as the summon key: currently unused in ZenTab, ergonomic, no conflict. Some
  switchers use `Space` for Quick Look preview; ZenTab has no preview, so it is free.

## Principles check

- **Performance:** the strip is the `Cmd+Tab` set already in hand; animations are CALayer
  on the existing recycled tiles. No new hot-path enumeration.
- **Opinionated and minimal:** one board, two verbs, fixed behavior. Nothing here is a
  setting; only the trigger keys stay configurable, as everywhere else.
- **No SIP, no sandbox compromise:** summon/fling use App-Sandbox-off private CGS only;
  the one thing that would have needed more (Space-creation) is cut.
