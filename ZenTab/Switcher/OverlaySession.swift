import CoreGraphics
import Foundation

/// The pure decision logic for one switcher invocation: tap-vs-hold, the deferred
/// overlay show, "confirm always wins", and the two-zone curation board. It is
/// deliberately free of AppKit, timers, and enumeration so every scenario (including the
/// nasty timing bugs) is unit-testable. `OverlayController` is a thin shell that runs the
/// `Effect`s this emits and feeds events back.
///
/// The board: in the multi-Space modes the window list is split at `hereStart` into an
/// ELSEWHERE grid (`windows[0..<hereStart]`, not on the current Space) above a HERE strip
/// (`windows[hereStart...]`, on the current Space). Summon pulls a grid window down into
/// the strip; fling sends a window off the current Space (and out of the overlay). The
/// list stays flat so the tested tap/hold/cycle/close machinery is unchanged; the split is
/// just an index the view renders around.
///
/// Timing safety: each invocation has a `session` id. The deferred-show timer and the
/// enumeration both carry the id they were started for; `confirm`/`cancel` bump the session
/// via `finish`, so a stale timer firing afterward is ignored and can never re-open the
/// overlay (the "quick tap leaves the UI stuck" bug).
struct OverlaySession: Equatable {
  enum Event: Equatable {
    case summon
    /// `hereIDs` are the windows on the current Space (for the grid/strip split); `usesBoard`
    /// is whether this mode shows the board at all. `currentPID` is the focused app, so a
    /// non-board (flat) list can skip the focused window — a quick tap switches to the previous.
    case enumerated([WindowInfo], hereIDs: Set<CGWindowID>, usesBoard: Bool, currentPID: pid_t?, session: Int)
    case holdElapsed(session: Int)
    case cycle(backward: Bool)
    case confirm
    case cancel
    case hover(Int)
    /// W: close the selected window (overlay stays up, modifier still held).
    case closeSelected
    /// Q: quit the selected window's whole app (all its windows go with it).
    case quitSelected
    /// ↓ / Space: summon the selected ELSEWHERE window to the current Space (into the strip).
    case summonSelected
    /// ↑ / ← / → : fling the selected window off the current Space (it leaves; you stay put).
    case flingSelected(FlingDirection)
  }

  enum Effect: Equatable {
    /// Kick off off-main window enumeration for this session.
    case beginEnumeration(session: Int)
    /// Start the hold timer; deliver `.holdElapsed(session:)` when it fires.
    case scheduleHold(session: Int)
    /// Show the overlay with these windows, the grid/strip split, and selection.
    case show(windows: [WindowInfo], hereStart: Int, index: Int)
    /// Move the selection highlight (overlay already visible).
    case updateSelection(Int)
    /// Re-lay the grid/strip after a move, close, or quit changed the list.
    case relayout(windows: [WindowInfo], hereStart: Int, index: Int)
    /// Dismiss the overlay.
    case hide
    /// Focus this window (nil = nothing to focus, e.g. cancel or empty list).
    case focus(WindowInfo?)
    /// Close this window (press its AX close button).
    case close(WindowInfo)
    /// Quit this app (terminate every window it owns).
    case quit(pid_t)
    /// Summon this window to the current Space (bring here). The controller animates the
    /// tile flying down into the strip on the relayout that follows.
    case summonWindow(WindowInfo)
    /// Fling this window off the current Space. The controller animates the tile flying off
    /// the matching edge on the relayout that follows.
    case flingWindow(WindowInfo, FlingDirection)
  }

  private(set) var session = 0
  private var windows: [WindowInfo] = []
  /// Split point: `windows[0..<hereStart]` is the ELSEWHERE grid, `windows[hereStart...]`
  /// the HERE strip. `0` or `count` (one zone) renders as a flat grid.
  private(set) var hereStart = 0
  private var usesBoard = false
  private var windowsReady = false
  private var confirmRequested = false
  private var wantsShow = false
  private var pendingSteps = 0
  private var index = 0
  private(set) var isVisible = false

  var selected: WindowInfo? { windows.indices.contains(index) ? windows[index] : nil }
  /// Whether the current selection is an ELSEWHERE (grid) window — the only kind summon acts on.
  private var selectionIsElsewhere: Bool { index < hereStart }

  mutating func handle(_ event: Event) -> [Effect] {
    switch event {
    case .summon: return summon()
    case .enumerated(let list, let hereIDs, let board, let pid, let id):
      return enumerated(list, hereIDs: hereIDs, usesBoard: board, currentPID: pid, session: id)
    case .holdElapsed(let id): return holdElapsed(session: id)
    case .cycle(let backward): return cycle(backward: backward)
    case .confirm: return confirm()
    case .cancel: return finish(focus: nil)
    case .hover(let i): return hover(i)
    case .closeSelected: return closeSelected()
    case .quitSelected: return quitSelected()
    case .summonSelected: return summonSelected()
    case .flingSelected(let direction): return flingSelected(direction)
    }
  }

  private mutating func summon() -> [Effect] {
    session += 1
    windows = []
    hereStart = 0
    usesBoard = false
    windowsReady = false
    confirmRequested = false
    wantsShow = false
    pendingSteps = 0
    index = 0
    var effects: [Effect] = []
    if isVisible {
      isVisible = false
      effects.append(.hide)  // defensive: clear a stale overlay
    }
    effects.append(.beginEnumeration(session: session))
    effects.append(.scheduleHold(session: session))
    return effects
  }

  private mutating func enumerated(
    _ list: [WindowInfo], hereIDs: Set<CGWindowID>, usesBoard board: Bool, currentPID: pid_t?,
    session id: Int
  ) -> [Effect] {
    guard id == session else { return [] }  // superseded by a newer summon / finish
    usesBoard = board
    if board {
      // Partition into ELSEWHERE (grid) then HERE (strip), each keeping the enumerator's order.
      let elsewhere = list.filter { !hereIDs.contains($0.windowID) }
      let here = list.filter { hereIDs.contains($0.windowID) }
      windows = elsewhere + here
      hereStart = elsewhere.count
    } else {
      // Flat (current-Space-only) mode: every window is HERE, so there is no grid. hereStart
      // 0 ⇒ a single flat grid in the view and summon is a no-op (nothing is "elsewhere").
      windows = list
      hereStart = 0
    }
    windowsReady = true

    let count = windows.count
    if count == 0 {
      index = 0
      pendingSteps = 0
      return update()
    }
    // A true two-zone board starts on the first ELSEWHERE window (you pull from there);
    // a flat list keeps the Cmd+Tab "start one past the focused window" behavior.
    let twoZone = hereStart > 0 && hereStart < count
    let base = twoZone ? 0 : (windows.firstIndex { $0.pid == currentPID }.map { $0 + 1 } ?? 0)
    index = ((base + pendingSteps) % count + count) % count
    pendingSteps = 0
    return update()
  }

  private mutating func holdElapsed(session id: Int) -> [Effect] {
    guard id == session else { return [] }  // stale timer (already confirmed/cancelled)
    wantsShow = true
    return update()
  }

  private mutating func cycle(backward: Bool) -> [Effect] {
    guard windowsReady, !windows.isEmpty else {
      pendingSteps += backward ? -1 : 1
      return []
    }
    let modulo = windows.count
    index = ((index + (backward ? -1 : 1)) % modulo + modulo) % modulo
    return isVisible ? [.updateSelection(index)] : []
  }

  private mutating func confirm() -> [Effect] {
    confirmRequested = true
    return update()
  }

  private mutating func hover(_ i: Int) -> [Effect] {
    guard windows.indices.contains(i) else { return [] }
    index = i
    return isVisible ? [.updateSelection(index)] : []
  }

  /// W: close the selected window. Optimistically drop it and re-lay the grid (the actual
  /// AX close is a side effect), so the UI never waits on the close. Hold-only.
  private mutating func closeSelected() -> [Effect] {
    guard isVisible, let target = selected else { return [] }
    var effects: [Effect] = [.close(target)]
    removeWindows { $0.windowID == target.windowID }
    effects += relayoutOrHide()
    return effects
  }

  /// Q: quit the selected window's whole app — optimistically drop *every* window of that
  /// app, then re-lay (or hide). Mirrors `closeSelected`; the terminate is a side effect.
  private mutating func quitSelected() -> [Effect] {
    guard isVisible, let target = selected else { return [] }
    let pid = target.pid
    var effects: [Effect] = [.quit(pid)]
    removeWindows { $0.pid == pid }
    effects += relayoutOrHide()
    return effects
  }

  /// ↓ / Space: summon the selected ELSEWHERE window to the current Space — it moves down
  /// into the HERE strip and the grid selection advances to the next elsewhere window, so
  /// rapid Space gathers a set. A no-op if the selection is already here (or the list is
  /// flat). The real move + the fly-down animation are side effects.
  private mutating func summonSelected() -> [Effect] {
    guard isVisible, let target = selected, selectionIsElsewhere else { return [] }
    let moved = windows.remove(at: index)  // an elsewhere window
    hereStart -= 1
    windows.append(moved)  // it is now the last HERE window
    // Stay in the grid on the next elsewhere window; if the grid just emptied, fall to the strip.
    index = hereStart > 0 ? min(index, hereStart - 1) : 0
    return [.summonWindow(target), .relayout(windows: windows, hereStart: hereStart, index: index)]
  }

  /// ↑ / ← / → : fling the selected window off the current Space. It leaves, so it is dropped
  /// from the overlay (which is also what keeps "you stay put": release can't follow a window
  /// that is no longer selectable). The real move, the edge no-op, and the fly-off animation
  /// are side effects.
  private mutating func flingSelected(_ direction: FlingDirection) -> [Effect] {
    guard isVisible, let target = selected else { return [] }
    var effects: [Effect] = [.flingWindow(target, direction)]
    removeWindows { $0.windowID == target.windowID }
    effects += relayoutOrHide()
    return effects
  }

  /// Remove matching windows, keeping both the selection and the grid/strip split valid: the
  /// selection lands on the window that followed the removed one, and `hereStart` shrinks by
  /// however many removed windows were in the grid.
  private mutating func removeWindows(where shouldRemove: (WindowInfo) -> Bool) {
    let removedBeforeIndex = windows[..<index].lazy.filter(shouldRemove).count
    let removedInGrid = windows[..<hereStart].lazy.filter(shouldRemove).count
    windows.removeAll(where: shouldRemove)
    hereStart = max(0, hereStart - removedInGrid)
    index = windows.isEmpty ? 0 : min(max(0, index - removedBeforeIndex), windows.count - 1)
  }

  /// After a change: re-lay the surviving grid/strip, or hide if nothing is left (the session
  /// stays alive, so a later release just focuses nothing).
  private mutating func relayoutOrHide() -> [Effect] {
    if windows.isEmpty {
      isVisible = false
      return [.hide]
    }
    return [.relayout(windows: windows, hereStart: hereStart, index: index)]
  }

  /// The single decision point. A requested confirm always wins: the overlay is never shown
  /// once the modifier has been released.
  private mutating func update() -> [Effect] {
    if confirmRequested {
      guard windowsReady else { return [] }  // wait for enumeration, then focus
      return finish(focus: selected)
    }
    if wantsShow, windowsReady, !isVisible, !windows.isEmpty {
      isVisible = true
      return [.show(windows: windows, hereStart: hereStart, index: index)]
    }
    return []
  }

  private mutating func finish(focus target: WindowInfo?) -> [Effect] {
    session += 1  // invalidate any pending enumeration / hold timer for this invocation
    let wasVisible = isVisible
    windows = []
    hereStart = 0
    usesBoard = false
    windowsReady = false
    confirmRequested = false
    wantsShow = false
    pendingSteps = 0
    index = 0
    isVisible = false
    var effects: [Effect] = []
    if wasVisible { effects.append(.hide) }
    effects.append(.focus(target))
    return effects
  }
}
