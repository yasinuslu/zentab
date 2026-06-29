import CoreGraphics
import Testing

@testable import ZenTab

/// Tests for the switcher's tap-vs-hold / show / confirm logic — the exact behavior
/// that was buggy on-device (quick tap showed the overlay; the overlay got stuck).
/// Driving the pure `OverlaySession` lets us reproduce the timing without a running
/// app, so these regressions are caught headlessly.
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

  // The bug: a quick Ctrl+Opt+Tab tap showed the overlay and then got stuck.
  @Test("Quick tap focuses the first window without ever showing the overlay")
  func quickTapNeverShows() {
    var session = OverlaySession()
    let list = windows(3)

    let onSummon = session.handle(.summon)
    #expect(onSummon == [.beginEnumeration(session: 1), .scheduleHold(session: 1)])

    // Enumeration finishes fast; nothing should display yet (no hold, no confirm).
    #expect(session.handle(.enumerated(list, currentPID: nil, session: 1)).isEmpty)
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
    _ = session.handle(.enumerated(list, currentPID: 100, session: 1))
    #expect(session.handle(.confirm) == [.focus(list[1])])  // previous, not list[0]
  }

  @Test("Holding starts the highlight on the window after the focused one")
  func holdStartsAfterFocusedWindow() {
    var session = OverlaySession()
    let list = windows(3)
    _ = session.handle(.summon)
    _ = session.handle(.enumerated(list, currentPID: 100, session: 1))
    #expect(session.handle(.holdElapsed(session: 1)) == [.show(windows: list, index: 1)])
  }

  @Test("When the focused app has no window here, selection starts at the front")
  func focusedAppNotInListStartsAtFront() {
    var session = OverlaySession()
    let list = windows(3)
    _ = session.handle(.summon)
    _ = session.handle(.enumerated(list, currentPID: 999, session: 1))  // 999 not in list
    #expect(session.handle(.confirm) == [.focus(list[0])])
  }

  // The "stuck" half: the deferred hold timer must not re-open the overlay after a
  // quick tap already confirmed.
  @Test("A hold timer that fires after a quick tap is ignored (no stuck overlay)")
  func staleHoldTimerDoesNotReshow() {
    var session = OverlaySession()
    let list = windows(2)
    _ = session.handle(.summon)  // session 1
    _ = session.handle(.enumerated(list, currentPID: nil, session: 1))
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
    _ = session.handle(.enumerated(list, currentPID: nil, session: 1))

    #expect(session.handle(.holdElapsed(session: 1)) == [.show(windows: list, index: 0)])
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
    #expect(session.handle(.enumerated(list, currentPID: nil, session: 1)) == [.focus(list[0])])
    #expect(!session.isVisible)
  }

  @Test("Cycle before enumeration is buffered into the starting selection")
  func cycleBufferedUntilReady() {
    var session = OverlaySession()
    let list = windows(3)
    _ = session.handle(.summon)
    #expect(session.handle(.cycle(backward: false)).isEmpty)
    #expect(session.handle(.cycle(backward: false)).isEmpty)
    _ = session.handle(.enumerated(list, currentPID: nil, session: 1))

    // Two forward steps from 0 -> index 2; the hold then shows that selection.
    #expect(session.handle(.holdElapsed(session: 1)) == [.show(windows: list, index: 2)])
  }

  @Test("Cycle wraps while the overlay is visible")
  func cycleWrapsWhenVisible() {
    var session = OverlaySession()
    let list = windows(2)
    _ = session.handle(.summon)
    _ = session.handle(.enumerated(list, currentPID: nil, session: 1))
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
    #expect(session.handle(.enumerated(windows(5), currentPID: nil, session: 1)).isEmpty)
    #expect(!session.isVisible)
  }

  @Test("Cancel (Esc) hides without focusing")
  func cancelHidesNoFocus() {
    var session = OverlaySession()
    let list = windows(2)
    _ = session.handle(.summon)
    _ = session.handle(.enumerated(list, currentPID: nil, session: 1))
    _ = session.handle(.holdElapsed(session: 1))  // visible

    #expect(session.handle(.cancel) == [.hide, .focus(nil)])
    #expect(!session.isVisible)
  }

  @Test("An empty window list never shows and focuses nothing")
  func emptyListShowsNothing() {
    var session = OverlaySession()
    _ = session.handle(.summon)
    _ = session.handle(.enumerated([], currentPID: nil, session: 1))
    #expect(session.handle(.holdElapsed(session: 1)).isEmpty)  // nothing to show
    #expect(!session.isVisible)
    #expect(session.handle(.confirm) == [.focus(nil)])
  }

  @Test("Hover before the overlay is visible moves selection silently")
  func hoverSilentWhenHidden() {
    var session = OverlaySession()
    let list = windows(3)
    _ = session.handle(.summon)
    _ = session.handle(.enumerated(list, currentPID: nil, session: 1))
    // Not shown yet: hover updates internal selection but emits no view effect.
    #expect(session.handle(.hover(2)).isEmpty)
    #expect(session.handle(.holdElapsed(session: 1)) == [.show(windows: list, index: 2)])
  }
}
