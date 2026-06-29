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
    case enumerated([WindowInfo], session: Int)
    case holdElapsed(session: Int)
    case cycle(backward: Bool)
    case confirm
    case cancel
    case hover(Int)
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
    /// Dismiss the overlay.
    case hide
    /// Focus this window (nil = nothing to focus, e.g. cancel or empty list).
    case focus(WindowInfo?)
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
    case .enumerated(let list, let id): return enumerated(list, session: id)
    case .holdElapsed(let id): return holdElapsed(session: id)
    case .cycle(let backward): return cycle(backward: backward)
    case .confirm: return confirm()
    case .cancel: return finish(focus: nil)
    case .hover(let i): return hover(i)
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

  private mutating func enumerated(_ list: [WindowInfo], session id: Int) -> [Effect] {
    guard id == session else { return [] }  // superseded by a newer summon / finish
    windows = list
    windowsReady = true
    index = list.isEmpty ? 0 : ((pendingSteps % list.count) + list.count) % list.count
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
