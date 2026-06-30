import Foundation

/// The pure decision logic for one switcher invocation: tap-vs-hold, the deferred
/// overlay show, and "confirm always wins". It is deliberately free of AppKit,
/// timers, and enumeration so every scenario (including the nasty timing bugs) is
/// unit-testable. `OverlayController` is a thin shell that runs the `Effect`s this
/// emits and feeds events back.
///
/// Timing safety: each invocation has a `session` id. The deferred-show timer and
/// the enumeration both carry the id they were started for; `confirm`/`cancel`
/// bump the session via `finish`, so a stale timer firing afterward is ignored and
/// can never re-open the overlay (the "quick tap leaves the UI stuck" bug).
struct OverlaySession: Equatable {
  enum Event: Equatable {
    case summon
    /// `currentPID` is the focused app, so the initial selection can skip the
    /// focused window — a quick tap then switches to the previous window.
    case enumerated([WindowInfo], currentPID: pid_t?, session: Int)
    case holdElapsed(session: Int)
    case cycle(backward: Bool)
    case confirm
    case cancel
    case hover(Int)
    /// W: close the selected window (overlay stays up, modifier still held).
    case closeSelected
    /// Q: quit the selected window's whole app (all its windows go with it).
    case quitSelected
    /// Space: summon the selected window to the current Space (it comes here; tile stays).
    case summonSelected
    /// ←/→: fling the selected window to the adjacent Space (it leaves; you stay put).
    case flingSelected(FlingDirection)
  }

  enum Effect: Equatable {
    /// Kick off off-main window enumeration for this session.
    case beginEnumeration(session: Int)
    /// Start the hold timer; deliver `.holdElapsed(session:)` when it fires.
    case scheduleHold(session: Int)
    /// Show the overlay with these windows and selection.
    case show(windows: [WindowInfo], index: Int)
    /// Move the selection highlight (overlay already visible).
    case updateSelection(Int)
    /// Re-lay the (now shorter) grid after a close/quit removed windows.
    case relayout(windows: [WindowInfo], index: Int)
    /// Dismiss the overlay.
    case hide
    /// Focus this window (nil = nothing to focus, e.g. cancel or empty list).
    case focus(WindowInfo?)
    /// Close this window (press its AX close button).
    case close(WindowInfo)
    /// Quit this app (terminate every window it owns).
    case quit(pid_t)
    /// Summon this window to the current Space (bring here).
    case summonWindow(WindowInfo)
    /// Fling this window to the adjacent Space in the given direction (send away).
    case flingWindow(WindowInfo, FlingDirection)
  }

  private(set) var session = 0
  private var windows: [WindowInfo] = []
  private var windowsReady = false
  private var confirmRequested = false
  private var wantsShow = false
  private var pendingSteps = 0
  private var index = 0
  private(set) var isVisible = false

  var selected: WindowInfo? { windows.indices.contains(index) ? windows[index] : nil }

  mutating func handle(_ event: Event) -> [Effect] {
    switch event {
    case .summon: return summon()
    case .enumerated(let list, let pid, let id):
      return enumerated(list, currentPID: pid, session: id)
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
    _ list: [WindowInfo], currentPID: pid_t?, session id: Int
  ) -> [Effect] {
    guard id == session else { return [] }  // superseded by a newer summon / finish
    windows = list
    windowsReady = true
    // Start one past the focused window (Cmd+Tab style), so a quick tap switches to
    // the previous window rather than the one you're already in. If the focused app
    // has no window here (e.g. it's on another monitor), start at the front (0).
    let base = list.firstIndex { $0.pid == currentPID }.map { $0 + 1 } ?? 0
    index = list.isEmpty ? 0 : ((base + pendingSteps) % list.count + list.count) % list.count
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

  /// W: close the selected window. Optimistically drop it from the list and re-lay
  /// the grid (the actual AX close runs as a side effect), so the UI never waits on
  /// the close. A hold-only action: a no-op unless the overlay is up. The session
  /// stays alive — the modifier is still held — so you can keep closing or navigate.
  private mutating func closeSelected() -> [Effect] {
    guard isVisible, let target = selected else { return [] }
    var effects: [Effect] = [.close(target)]
    removeWindows { $0.windowID == target.windowID }
    effects += relayoutOrHide()
    return effects
  }

  /// Q: quit the selected window's whole app — optimistically drop *every* window of
  /// that app, then re-lay (or hide). Mirrors `closeSelected`; the terminate is a
  /// side effect.
  private mutating func quitSelected() -> [Effect] {
    guard isVisible, let target = selected else { return [] }
    let pid = target.pid
    var effects: [Effect] = [.quit(pid)]
    removeWindows { $0.pid == pid }
    effects += relayoutOrHide()
    return effects
  }

  /// Space: summon the selected window to the current Space. It comes to you, so the tile
  /// stays in the list (the window still exists; it is just here now) and the overlay stays
  /// up — rapid Space-Space gathers a set. A hold-only action. The move is a side effect.
  private mutating func summonSelected() -> [Effect] {
    guard isVisible, let target = selected else { return [] }
    return [.summonWindow(target)]
  }

  /// Arrow: fling the selected window to the adjacent Space. The window leaves this Space,
  /// so it is dropped from the overlay (mirrors close/quit) — that is also what keeps
  /// "you stay put": release can't follow a window that is no longer selectable. The actual
  /// move (and the edge no-op, where no adjacent Space exists) is the side effect.
  private mutating func flingSelected(_ direction: FlingDirection) -> [Effect] {
    guard isVisible, let target = selected else { return [] }
    var effects: [Effect] = [.flingWindow(target, direction)]
    removeWindows { $0.windowID == target.windowID }
    effects += relayoutOrHide()
    return effects
  }

  /// Remove matching windows and keep the selection on a sensible neighbor: it lands
  /// on the window that followed the removed selection (or the new last one).
  private mutating func removeWindows(where shouldRemove: (WindowInfo) -> Bool) {
    let removedBeforeIndex = windows[..<index].lazy.filter(shouldRemove).count
    windows.removeAll(where: shouldRemove)
    index = windows.isEmpty ? 0 : min(max(0, index - removedBeforeIndex), windows.count - 1)
  }

  /// After a removal: re-lay the surviving grid, or hide if nothing is left (the
  /// session stays alive, so a later release just focuses nothing).
  private mutating func relayoutOrHide() -> [Effect] {
    if windows.isEmpty {
      isVisible = false
      return [.hide]
    }
    return [.relayout(windows: windows, index: index)]
  }

  /// The single decision point. A requested confirm always wins: the overlay is
  /// never shown once the modifier has been released.
  private mutating func update() -> [Effect] {
    if confirmRequested {
      guard windowsReady else { return [] }  // wait for enumeration, then focus
      return finish(focus: selected)
    }
    if wantsShow, windowsReady, !isVisible, !windows.isEmpty {
      isVisible = true
      return [.show(windows: windows, index: index)]
    }
    return []
  }

  private mutating func finish(focus target: WindowInfo?) -> [Effect] {
    session += 1  // invalidate any pending enumeration / hold timer for this invocation
    let wasVisible = isVisible
    windows = []
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
