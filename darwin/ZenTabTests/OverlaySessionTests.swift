import CoreGraphics
import Testing

@testable import ZenTab

/// Tests for the switcher's tap-vs-hold / show / confirm logic and the two-zone curation
/// board — the exact behavior that was buggy on-device (quick tap showed the overlay; the
/// overlay got stuck) plus the grid/strip moves. Driving the pure `OverlaySession` lets us
/// reproduce the timing and the moves without a running app, so these are caught headlessly.
@Suite("OverlaySession")
struct OverlaySessionTests {
  typealias Effect = OverlaySession.Effect

  private func windows(_ count: Int) -> [WindowInfo] {
    (0..<count).map { i in
      WindowInfo(
        pid: pid_t(100 + i), windowID: CGWindowID(1000 + i), title: "W\(i)", appName: "App\(i)",
        frame: CGRect(x: 0, y: 0, width: 400, height: 300), isMinimized: false,
        subrole: "AXStandardWindow")
    }
  }

  /// A window with an explicit pid/windowID, for the close/quit selection-math tests
  /// (where several windows must share an app pid).
  private func window(pid: pid_t, wid: CGWindowID) -> WindowInfo {
    WindowInfo(
      pid: pid, windowID: wid, title: "W\(wid)", appName: "App\(pid)",
      frame: CGRect(x: 0, y: 0, width: 400, height: 300), isMinimized: false,
      subrole: "AXStandardWindow")
  }

  /// A flat (current-Space-only) enumeration: no board, nothing "elsewhere".
  private func flat(_ list: [WindowInfo], currentPID: pid_t? = nil, session: Int = 1) -> OverlaySession.Event {
    .enumerated(list, hereIDs: [], usesBoard: false, currentPID: currentPID, session: session)
  }

  /// A board enumeration where the LAST `hereCount` windows are on the current Space (the
  /// HERE strip) and the rest are ELSEWHERE (the grid). Order is preserved, so the resulting
  /// `windows == list` with `hereStart == list.count - hereCount`.
  private func board(_ list: [WindowInfo], hereCount: Int, session: Int = 1) -> OverlaySession.Event {
    let hereIDs = Set(list.suffix(hereCount).map(\.windowID))
    return .enumerated(list, hereIDs: hereIDs, usesBoard: true, currentPID: nil, session: session)
  }

  // The bug: a quick Ctrl+Opt+Tab tap showed the overlay and then got stuck.
  @Test("Quick tap focuses the first window without ever showing the overlay")
  func quickTapNeverShows() {
    var session = OverlaySession()
    let list = windows(3)

    let onSummon = session.handle(.summon)
    #expect(onSummon == [.beginEnumeration(session: 1), .scheduleHold(session: 1)])

    // Enumeration finishes fast; nothing should display yet (no hold, no confirm).
    #expect(session.handle(flat(list)).isEmpty)
    #expect(!session.isVisible)

    // Modifier released before the hold threshold -> confirm. Focus, no overlay.
    #expect(session.handle(.confirm) == [.focus(list[0])])
    #expect(!session.isVisible)
  }

  // The current app is now in the list; a quick tap must still switch *away* from
  // the focused window (to the previous one), not to the window you're already in.
  @Test("Quick tap skips the focused window and switches to the previous one")
  func quickTapSkipsFocusedWindow() {
    var session = OverlaySession()
    let list = windows(3)  // pids 100, 101, 102; list[0] is the focused window
    _ = session.handle(.summon)
    _ = session.handle(flat(list, currentPID: 100))
    #expect(session.handle(.confirm) == [.focus(list[1])])  // previous, not list[0]
  }

  @Test("Holding starts the highlight on the window after the focused one")
  func holdStartsAfterFocusedWindow() {
    var session = OverlaySession()
    let list = windows(3)
    _ = session.handle(.summon)
    _ = session.handle(flat(list, currentPID: 100))
    #expect(session.handle(.holdElapsed(session: 1)) == [.show(windows: list, hereStart: 0, index: 1)])
  }

  @Test("When the focused app has no window here, selection starts at the front")
  func focusedAppNotInListStartsAtFront() {
    var session = OverlaySession()
    let list = windows(3)
    _ = session.handle(.summon)
    _ = session.handle(flat(list, currentPID: 999))  // 999 not in list
    #expect(session.handle(.confirm) == [.focus(list[0])])
  }

  // The "stuck" half: the deferred hold timer must not re-open the overlay after a
  // quick tap already confirmed.
  @Test("A hold timer that fires after a quick tap is ignored (no stuck overlay)")
  func staleHoldTimerDoesNotReshow() {
    var session = OverlaySession()
    let list = windows(2)
    _ = session.handle(.summon)  // session 1
    _ = session.handle(flat(list))
    _ = session.handle(.confirm)  // finishes -> session bumped to 2

    // The 150ms timer (scheduled for session 1) now fires late:
    #expect(session.handle(.holdElapsed(session: 1)).isEmpty)
    #expect(!session.isVisible)
  }

  @Test("Holding past the threshold shows the overlay, then release focuses + hides")
  func holdShowsThenConfirms() {
    var session = OverlaySession()
    let list = windows(3)
    _ = session.handle(.summon)
    _ = session.handle(flat(list))

    #expect(session.handle(.holdElapsed(session: 1)) == [.show(windows: list, hereStart: 0, index: 0)])
    #expect(session.isVisible)

    #expect(session.handle(.confirm) == [.hide, .focus(list[0])])
    #expect(!session.isVisible)
  }

  @Test("Confirm before enumeration completes waits, then focuses when ready")
  func confirmBeforeEnumeration() {
    var session = OverlaySession()
    let list = windows(2)
    _ = session.handle(.summon)

    #expect(session.handle(.confirm).isEmpty)  // nothing to focus yet
    #expect(session.handle(flat(list)) == [.focus(list[0])])
    #expect(!session.isVisible)
  }

  @Test("Cycle before enumeration is buffered into the starting selection")
  func cycleBufferedUntilReady() {
    var session = OverlaySession()
    let list = windows(3)
    _ = session.handle(.summon)
    #expect(session.handle(.cycle(backward: false)).isEmpty)
    #expect(session.handle(.cycle(backward: false)).isEmpty)
    _ = session.handle(flat(list))

    // Two forward steps from 0 -> index 2; the hold then shows that selection.
    #expect(session.handle(.holdElapsed(session: 1)) == [.show(windows: list, hereStart: 0, index: 2)])
  }

  @Test("Cycle wraps while the overlay is visible")
  func cycleWrapsWhenVisible() {
    var session = OverlaySession()
    let list = windows(2)
    _ = session.handle(.summon)
    _ = session.handle(flat(list))
    _ = session.handle(.holdElapsed(session: 1))  // visible at 0

    #expect(session.handle(.cycle(backward: false)) == [.updateSelection(1)])
    #expect(session.handle(.cycle(backward: false)) == [.updateSelection(0)])  // wrapped
    #expect(session.handle(.cycle(backward: true)) == [.updateSelection(1)])  // back-wrap
  }

  @Test("Stale enumeration from a previous summon is ignored")
  func staleEnumerationIgnored() {
    var session = OverlaySession()
    _ = session.handle(.summon)  // session 1
    _ = session.handle(.confirm)  // finish -> session 2 (no windows -> focus nil)
    _ = session.handle(.summon)  // session 3

    // A late enumeration tagged session 1 must not affect the live session 3.
    #expect(session.handle(flat(windows(5), session: 1)).isEmpty)
    #expect(!session.isVisible)
  }

  @Test("Cancel (Esc) hides without focusing")
  func cancelHidesNoFocus() {
    var session = OverlaySession()
    let list = windows(2)
    _ = session.handle(.summon)
    _ = session.handle(flat(list))
    _ = session.handle(.holdElapsed(session: 1))  // visible

    #expect(session.handle(.cancel) == [.hide, .focus(nil)])
    #expect(!session.isVisible)
  }

  @Test("An empty window list never shows and focuses nothing")
  func emptyListShowsNothing() {
    var session = OverlaySession()
    _ = session.handle(.summon)
    _ = session.handle(flat([]))
    #expect(session.handle(.holdElapsed(session: 1)).isEmpty)  // nothing to show
    #expect(!session.isVisible)
    #expect(session.handle(.confirm) == [.focus(nil)])
  }

  @Test("Hover before the overlay is visible moves selection silently")
  func hoverSilentWhenHidden() {
    var session = OverlaySession()
    let list = windows(3)
    _ = session.handle(.summon)
    _ = session.handle(flat(list))
    // Not shown yet: hover updates internal selection but emits no view effect.
    #expect(session.handle(.hover(2)).isEmpty)
    #expect(session.handle(.holdElapsed(session: 1)) == [.show(windows: list, hereStart: 0, index: 2)])
  }

  // MARK: - W = close / Q = quit

  @Test("W closes the selected window, keeps the overlay, selects the next one")
  func closeSelectedRelayouts() {
    var session = OverlaySession()
    let list = windows(3)
    _ = session.handle(.summon)
    _ = session.handle(flat(list))
    _ = session.handle(.holdElapsed(session: 1))  // visible at 0

    let remaining = [list[1], list[2]]
    #expect(
      session.handle(.closeSelected)
        == [.close(list[0]), .relayout(windows: remaining, hereStart: 0, index: 0)])
    #expect(session.isVisible)
    // Release now focuses the new selection, never the window we just closed.
    #expect(session.handle(.confirm) == [.hide, .focus(list[1])])
  }

  @Test("Closing a middle window keeps the selection on the following window")
  func closeMiddleKeepsNext() {
    var session = OverlaySession()
    let list = windows(4)
    _ = session.handle(.summon)
    _ = session.handle(flat(list))
    _ = session.handle(.holdElapsed(session: 1))
    _ = session.handle(.hover(1))  // select list[1]

    let remaining = [list[0], list[2], list[3]]
    #expect(
      session.handle(.closeSelected)
        == [.close(list[1]), .relayout(windows: remaining, hereStart: 0, index: 1)])
    #expect(session.handle(.confirm) == [.hide, .focus(list[2])])  // the next window
  }

  @Test("Closing the last window in the list clamps the selection to the new last")
  func closeLastClampsSelection() {
    var session = OverlaySession()
    let list = windows(3)
    _ = session.handle(.summon)
    _ = session.handle(flat(list))
    _ = session.handle(.holdElapsed(session: 1))
    _ = session.handle(.hover(2))  // select the last window

    let remaining = [list[0], list[1]]
    #expect(
      session.handle(.closeSelected)
        == [.close(list[2]), .relayout(windows: remaining, hereStart: 0, index: 1)])
    #expect(session.handle(.confirm) == [.hide, .focus(list[1])])
  }

  @Test("Closing the only window hides the overlay and focuses nothing on release")
  func closeOnlyWindowHides() {
    var session = OverlaySession()
    let list = windows(1)
    _ = session.handle(.summon)
    _ = session.handle(flat(list))
    _ = session.handle(.holdElapsed(session: 1))

    #expect(session.handle(.closeSelected) == [.close(list[0]), .hide])
    #expect(!session.isVisible)
    #expect(session.handle(.confirm) == [.focus(nil)])
  }

  @Test("Q quits the app, dropping every window that app owns")
  func quitRemovesAllAppWindows() {
    var session = OverlaySession()
    // Windows 1 and 2 share app pid 100; window 3 is a different app.
    let list = [window(pid: 100, wid: 1), window(pid: 100, wid: 2), window(pid: 200, wid: 3)]
    _ = session.handle(.summon)
    _ = session.handle(flat(list))
    _ = session.handle(.holdElapsed(session: 1))  // visible, selection at list[0] (pid 100)

    #expect(
      session.handle(.quitSelected)
        == [.quit(100), .relayout(windows: [list[2]], hereStart: 0, index: 0)])
    #expect(session.handle(.confirm) == [.hide, .focus(list[2])])
  }

  @Test("Quit adjusts the selection past app windows removed before it")
  func quitAdjustsSelectionForEarlierRemovals() {
    var session = OverlaySession()
    // pid 100 owns windows at indices 0 and 2; selecting index 2 then quitting drops
    // both, and the selection lands on what followed (the other app at the end).
    let list = [
      window(pid: 100, wid: 1), window(pid: 200, wid: 2), window(pid: 100, wid: 3),
      window(pid: 300, wid: 4),
    ]
    _ = session.handle(.summon)
    _ = session.handle(flat(list))
    _ = session.handle(.holdElapsed(session: 1))
    _ = session.handle(.hover(2))  // select the second pid-100 window

    let remaining = [list[1], list[3]]
    #expect(
      session.handle(.quitSelected)
        == [.quit(100), .relayout(windows: remaining, hereStart: 0, index: 1)])
    #expect(session.handle(.confirm) == [.hide, .focus(list[3])])
  }

  @Test("W / Q do nothing before the overlay is shown")
  func closeAndQuitIgnoredWhenHidden() {
    var session = OverlaySession()
    let list = windows(3)
    _ = session.handle(.summon)
    _ = session.handle(flat(list))
    // Enumerated but not held/shown: the action keys are inert.
    #expect(session.handle(.closeSelected).isEmpty)
    #expect(session.handle(.quitSelected).isEmpty)
    #expect(!session.isVisible)
    // A normal hold still shows the full, untouched list.
    #expect(session.handle(.holdElapsed(session: 1)) == [.show(windows: list, hereStart: 0, index: 0)])
  }

  // MARK: - The board: partition + ↓ summon / ↑←→ fling

  @Test("The board splits into ELSEWHERE grid + HERE strip and starts on the first grid tile")
  func boardSplitsAndStartsInGrid() {
    var session = OverlaySession()
    let list = windows(4)  // last 2 are HERE -> hereStart 2, grid = [0,1]
    _ = session.handle(.summon)
    _ = session.handle(board(list, hereCount: 2))
    // Shows split at hereStart 2, selection on the first ELSEWHERE window (index 0).
    #expect(session.handle(.holdElapsed(session: 1)) == [.show(windows: list, hereStart: 2, index: 0)])
  }

  @Test("↓ summons the selected grid window into the strip; selection advances in the grid")
  func summonMovesGridWindowToStrip() {
    var session = OverlaySession()
    let list = windows(4)
    _ = session.handle(.summon)
    _ = session.handle(board(list, hereCount: 2))  // windows [0 1 | 2 3], hereStart 2, index 0
    _ = session.handle(.holdElapsed(session: 1))

    // list[0] flies to the end of the strip; grid shrinks to [1]; next grid window (list[1])
    // is selected at index 0.
    let after = [list[1], list[2], list[3], list[0]]
    #expect(
      session.handle(.summonSelected)
        == [.summonWindow(list[0]), .relayout(windows: after, hereStart: 1, index: 0)])
    // Release now focuses the next grid window, which is what's selected.
    #expect(session.handle(.confirm) == [.hide, .focus(list[1])])
  }

  @Test("Summoning the last grid window empties the grid; selection falls into the strip")
  func summonLastGridWindowFallsToStrip() {
    var session = OverlaySession()
    let list = windows(3)
    _ = session.handle(.summon)
    _ = session.handle(board(list, hereCount: 2))  // windows [0 | 1 2], hereStart 1, index 0
    _ = session.handle(.holdElapsed(session: 1))

    let after = [list[1], list[2], list[0]]  // grid empty, strip = all
    #expect(
      session.handle(.summonSelected)
        == [.summonWindow(list[0]), .relayout(windows: after, hereStart: 0, index: 0)])
  }

  @Test("↓ is a no-op on a window that is already HERE (in the strip)")
  func summonNoOpOnHereWindow() {
    var session = OverlaySession()
    let list = windows(4)
    _ = session.handle(.summon)
    _ = session.handle(board(list, hereCount: 2))  // hereStart 2
    _ = session.handle(.holdElapsed(session: 1))
    _ = session.handle(.hover(2))  // select a HERE (strip) window
    #expect(session.handle(.summonSelected).isEmpty)
  }

  @Test("↓ / Space is a no-op in a flat (current-Space-only) list")
  func summonNoOpWhenFlat() {
    var session = OverlaySession()
    let list = windows(3)
    _ = session.handle(.summon)
    _ = session.handle(flat(list))
    _ = session.handle(.holdElapsed(session: 1))
    #expect(session.handle(.summonSelected).isEmpty)
  }

  @Test("Flinging a HERE window sends it away and drops it; the split is preserved")
  func flingHereWindowDropsItAndKeepsSplit() {
    var session = OverlaySession()
    let list = windows(4)
    _ = session.handle(.summon)
    _ = session.handle(board(list, hereCount: 2))  // [0 1 | 2 3], hereStart 2
    _ = session.handle(.holdElapsed(session: 1))
    _ = session.handle(.hover(2))  // select first HERE window (list[2])

    let remaining = [list[0], list[1], list[3]]  // grid intact, strip lost list[2]
    #expect(
      session.handle(.flingSelected(.away))
        == [.flingWindow(list[2], .away), .relayout(windows: remaining, hereStart: 2, index: 2)])
  }

  @Test("Flinging a grid window drops it and shrinks the grid")
  func flingGridWindowShrinksGrid() {
    var session = OverlaySession()
    let list = windows(4)
    _ = session.handle(.summon)
    _ = session.handle(board(list, hereCount: 2))  // [0 1 | 2 3], hereStart 2, index 0
    _ = session.handle(.holdElapsed(session: 1))

    let remaining = [list[1], list[2], list[3]]  // grid lost list[0] -> hereStart 1
    #expect(
      session.handle(.flingSelected(.left))
        == [.flingWindow(list[0], .left), .relayout(windows: remaining, hereStart: 1, index: 0)])
  }

  @Test("Fling carries its direction")
  func flingCarriesDirection() {
    var session = OverlaySession()
    let list = windows(2)
    _ = session.handle(.summon)
    _ = session.handle(flat(list))
    _ = session.handle(.holdElapsed(session: 1))
    #expect(session.handle(.flingSelected(.right)).first == .flingWindow(list[0], .right))
  }

  @Test("Flinging the only window hides the overlay")
  func flingOnlyWindowHides() {
    var session = OverlaySession()
    let list = windows(1)
    _ = session.handle(.summon)
    _ = session.handle(flat(list))
    _ = session.handle(.holdElapsed(session: 1))

    #expect(session.handle(.flingSelected(.right)) == [.flingWindow(list[0], .right), .hide])
    #expect(!session.isVisible)
    #expect(session.handle(.confirm) == [.focus(nil)])
  }

  @Test("Summon / fling do nothing before the overlay is shown")
  func summonFlingIgnoredWhenHidden() {
    var session = OverlaySession()
    let list = windows(3)
    _ = session.handle(.summon)
    _ = session.handle(board(list, hereCount: 1))
    #expect(session.handle(.summonSelected).isEmpty)
    #expect(session.handle(.flingSelected(.left)).isEmpty)
    #expect(!session.isVisible)
  }
}
