import AppKit
import CoreGraphics

/// One `CGEventTap` on a dedicated background-thread runloop. It watches several
/// trigger chords (one per `SwitchMode`) and reports which one fired (summon on
/// first key-down, cycle on subsequent ones while held), the trigger-modifier
/// *release* (confirm, via `.flagsChanged` — which survives secure input where key
/// events don't), and Esc (cancel). The C tap callback runs on the tap thread and
/// must return its absorb/pass decision synchronously; all switcher work is hopped
/// to the main actor.
///
/// `@unchecked Sendable`: `triggers`/`handlers` are immutable; `active`/`activeHold`,
/// `machPort` and `runLoop` are lock-guarded (`recreate` swaps them); `thread` is only
/// touched on the main actor.
final class HotkeyTap: @unchecked Sendable {
  /// A chord that triggers a given mode.
  struct Trigger {
    let mode: SwitchMode
    let binding: Keybinding
  }

  /// Main-actor callbacks driven by the tap.
  struct Handlers {
    let summon: @MainActor (_ mode: SwitchMode) -> Void
    let cycle: @MainActor (_ backward: Bool) -> Void
    let confirm: @MainActor () -> Void
    let cancel: @MainActor () -> Void
    let closeSelected: @MainActor () -> Void
    let quitSelected: @MainActor () -> Void
    let summonSelected: @MainActor () -> Void
    let flingSelected: @MainActor (_ direction: FlingDirection) -> Void
  }

  /// In-overlay action keys. Positional (like the triggers), and fixed — VISION makes
  /// the action *behavior* non-configurable; only the trigger keys vary. Space summons
  /// (bring here); ←/→ fling to the adjacent Space (send away). They are absorbed so the
  /// chord modifier (e.g. ⌘ held) can't fire the system shortcut underneath (⌘Space, etc.).
  private static let closeWindowKeyCode: CGKeyCode = 13  // W
  private static let quitAppKeyCode: CGKeyCode = 12  // Q
  private static let summonSpaceKeyCode: CGKeyCode = 49  // Space (summon alias)
  private static let summonDownKeyCode: CGKeyCode = 125  // ↓ (down into the HERE strip)
  private static let flingUpKeyCode: CGKeyCode = 126  // ↑ (send away)
  private static let flingLeftKeyCode: CGKeyCode = 123  // ←
  private static let flingRightKeyCode: CGKeyCode = 124  // →
  private static let escapeKeyCode: CGKeyCode = 53

  private let triggers: [Trigger]
  private let handlers: Handlers

  private let lock = NSLock()
  private var active = false
  /// The held modifiers of the chord that summoned; releasing any of them confirms.
  private var activeHold: NSEvent.ModifierFlags = []
  /// Arrival times (uptime ns) of trigger key-downs the tap acted on in the last second,
  /// so the Carbon fallback can drop its echo of a press the tap already handled.
  private var recentTapTriggers: [UInt64] = []

  private var machPort: CFMachPort?
  private var runLoop: CFRunLoop?
  private var thread: Thread?

  init(triggers: [Trigger], handlers: Handlers) {
    self.triggers = triggers
    self.handlers = handlers
  }

  /// Create + start the tap. Returns false if `CGEvent.tapCreate` fails, which is
  /// what happens without Accessibility permission — the caller surfaces that.
  @discardableResult
  func start() -> Bool {
    let mask: CGEventMask =
      (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
    guard
      let port = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: Self.callback,
        userInfo: Unmanaged.passUnretained(self).toOpaque())
    else { return false }

    lock.lock()
    machPort = port
    lock.unlock()
    // Hand the port to the thread directly (boxed: CFMachPort isn't Sendable), so a
    // later `recreate` swapping `machPort` can't race this thread's setup.
    let box = PortBox(port: port)
    let thread = Thread { [weak self] in
      guard let self else { return }
      let runLoop = CFRunLoopGetCurrent()
      self.lock.lock()
      self.runLoop = runLoop
      self.lock.unlock()
      let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, box.port, 0)
      CFRunLoopAddSource(runLoop, source, .commonModes)
      CGEvent.tapEnable(tap: box.port, enable: true)
      CFRunLoopRun()
    }
    thread.name = "org.nepjua.ZenTab.hotkey"
    thread.qualityOfService = .userInteractive
    self.thread = thread
    thread.start()
    return true
  }

  func stop() {
    lock.lock()
    let port = machPort
    let runLoop = self.runLoop
    machPort = nil
    self.runLoop = nil
    lock.unlock()
    if let port {
      CGEvent.tapEnable(tap: port, enable: false)
      CFMachPortInvalidate(port)
    }
    if let runLoop { CFRunLoopStop(runLoop) }
  }

  /// Throw the tap away and build a fresh one on a new thread. The heavy repair, for
  /// when re-enabling isn't enough: the port was invalidated, the tap thread died, or
  /// the system dropped the tap across sleep/wake or a display change. Session state
  /// (held chord, Carbon echo window) lives on `self`, so it survives.
  @discardableResult
  func recreate(reason: String) -> Bool {
    stop()
    let live = start()
    Log.input.notice(
      "tap re-created (\(reason, privacy: .public)): \(live ? "live" : "FAILED", privacy: .public)")
    return live
  }

  private var currentPort: CFMachPort? {
    lock.lock()
    defer { lock.unlock() }
    return machPort
  }

  /// Is the tap currently delivering events? The OS disables it on timeout / user
  /// input; the watchdog polls this so capture health reflects reality.
  var isEnabled: Bool {
    guard isAlive, let port = currentPort else { return false }
    return CGEvent.tapIsEnabled(tap: port)
  }

  /// Does the tap still exist at all: a valid port served by a running thread?
  /// `tapIsEnabled` alone can't tell a dead port or a stopped runloop from a live tap.
  var isAlive: Bool {
    guard let port = currentPort, CFMachPortIsValid(port), let thread else { return false }
    return !thread.isFinished
  }

  /// Re-enable the tap if the OS turned it off. Idempotent; cheap to call on a timer.
  /// This is the slow, belt-and-suspenders complement to the in-callback re-enable
  /// (which only fires on the explicit `tapDisabledBy*` events).
  func ensureEnabled() {
    reconcileHold()
    guard isAlive, let port = currentPort, !CGEvent.tapIsEnabled(tap: port) else { return }
    CGEvent.tapEnable(tap: port, enable: true)
    let live = CGEvent.tapIsEnabled(tap: port)
    Log.input.notice(
      "watchdog: tap found disabled, re-enabled: \(live ? "live" : "still off", privacy: .public)")
  }

  /// Test hook: switch the tap off the way the system can, without the
  /// `tapDisabledBy*` event, so the watchdog's re-enable path runs for real.
  func simulateSystemDisable() {
    if let port = currentPort { CGEvent.tapEnable(tap: port, enable: false) }
  }

  /// Test hook: kill the tap outright (invalidate the port, stop its runloop), the
  /// failure a re-enable can't fix, so the re-create path runs for real.
  func simulateTapDeath() {
    lock.lock()
    let port = machPort
    let runLoop = self.runLoop
    lock.unlock()
    if let port { CFMachPortInvalidate(port) }
    if let runLoop { CFRunLoopStop(runLoop) }
  }

  /// Confirm a session whose modifier release we never saw. The release arrives as a
  /// `.flagsChanged` event, which is lost if it lands while the tap is disabled (timeout,
  /// user input); the session would then stay "held" forever — the overlay stuck up, and
  /// every W/Q/Space/arrow absorbed. The physical key state is the ground truth.
  func reconcileHold() {
    let held = NSEvent.ModifierFlags(
      rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue))
    guard endSessionIfReleased(modifiers: held) else { return }
    dispatchMain { self.handlers.confirm() }
  }

  /// A trigger chord arrived through the Carbon hot-key fallback (`SecureInputHotkeys`),
  /// which still fires under Secure Event Input — when a password field or a terminal's
  /// secure keyboard entry is active, macOS stops delivering key-downs to event taps, and
  /// with the native Cmd+Tab disabled the shortcut would otherwise do nothing at all.
  /// Called on the main thread. A press the tap already acted on is dropped.
  func fallbackTriggerPressed(index: Int, backward: Bool) {
    guard triggers.indices.contains(index), !consumeTapEcho() else { return }
    triggerPressed(triggers[index], backward: backward, fromTap: false)
  }

  // MARK: - Tap-thread state (lock-guarded)

  private var snapshot: (active: Bool, hold: NSEvent.ModifierFlags) {
    lock.lock()
    defer { lock.unlock() }
    return (active, activeHold)
  }

  private func beginSession(hold: NSEvent.ModifierFlags) {
    lock.lock()
    active = true
    activeHold = hold
    lock.unlock()
  }

  private func endSession() {
    lock.lock()
    active = false
    activeHold = []
    lock.unlock()
  }

  /// Atomically end the session if `modifiers` no longer cover its hold, so the tap
  /// callback and `reconcileHold` can never both confirm the same release.
  private func endSessionIfReleased(modifiers: NSEvent.ModifierFlags) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard active,
      !modifiers.intersection(Keybinding.triggerModifierMask).isSuperset(of: activeHold)
    else { return false }
    active = false
    activeHold = []
    return true
  }

  private func recordTapTrigger() {
    let now = DispatchTime.now().uptimeNanoseconds
    lock.lock()
    recentTapTriggers.removeAll { now - $0 > Self.echoWindow }
    recentTapTriggers.append(now)
    lock.unlock()
  }

  /// Whether a fallback press is the echo of one the tap already handled.
  private func consumeTapEcho() -> Bool {
    let now = DispatchTime.now().uptimeNanoseconds
    lock.lock()
    defer { lock.unlock() }
    recentTapTriggers.removeAll { now - $0 > Self.echoWindow }
    guard !recentTapTriggers.isEmpty else { return false }
    recentTapTriggers.removeFirst()
    return true
  }

  private static let echoWindow: UInt64 = 1_000_000_000

  // MARK: - Callback

  /// Non-capturing closure, so it converts to the C `CGEventTapCallBack` pointer.
  private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HotkeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
  }

  private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    let passthrough = Unmanaged.passUnretained(event)

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      if let port = currentPort { CGEvent.tapEnable(tap: port, enable: true) }
      let cause = type == .tapDisabledByTimeout ? "timeout" : "user input"
      Log.input.notice("tap disabled by \(cause, privacy: .public); re-enabled")
      reconcileHold()  // the release may have happened while we were off
      return passthrough

    case .flagsChanged:
      let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
      if endSessionIfReleased(modifiers: modifiers) {
        dispatchMain { self.handlers.confirm() }
      }
      return passthrough  // never absorb modifier changes

    case .keyDown:
      let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
      let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
      // A key-down without the hold modifiers means the release was missed: the session
      // is stale. Drop it (no focus change — the user has moved on) and treat this key
      // fresh, instead of absorbing it as an in-overlay action.
      if endSessionIfReleased(modifiers: modifiers) {
        dispatchMain { self.handlers.cancel() }
      }
      // Absorb keys we handle so the focused app never sees the trigger / Esc.
      return handleKeyDown(keyCode: keyCode, modifiers: modifiers) ? nil : passthrough

    default:
      return passthrough
    }
  }

  /// Acts on a key-down and returns whether ZenTab consumed it.
  private func handleKeyDown(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags) -> Bool {
    if snapshot.active {
      switch keyCode {
      case Self.escapeKeyCode:  // Esc cancels
        endSession()
        dispatchMain { self.handlers.cancel() }
        return true
      case Self.closeWindowKeyCode:  // W closes the selected window
        dispatchMain { self.handlers.closeSelected() }
        return true
      case Self.quitAppKeyCode:  // Q quits the selected window's app
        dispatchMain { self.handlers.quitSelected() }
        return true
      case Self.summonDownKeyCode, Self.summonSpaceKeyCode:  // ↓ / Space: bring here
        dispatchMain { self.handlers.summonSelected() }
        return true
      case Self.flingUpKeyCode:  // ↑ sends the selected window away to an adjacent Space
        dispatchMain { self.handlers.flingSelected(.away) }
        return true
      case Self.flingLeftKeyCode:  // ← flings the selected window to the Space on the left
        dispatchMain { self.handlers.flingSelected(.left) }
        return true
      case Self.flingRightKeyCode:  // → flings it to the Space on the right
        dispatchMain { self.handlers.flingSelected(.right) }
        return true
      default:
        break
      }
    }

    guard
      let trigger = triggers.first(where: {
        $0.binding.matches(keyCode: keyCode, modifiers: modifiers)
      })
    else { return false }
    triggerPressed(trigger, backward: modifiers.contains(.shift), fromTap: true)
    return true
  }

  /// A trigger chord was pressed: the first press summons its mode, any trigger pressed
  /// again while held cycles. Shared by the tap and the Carbon fallback.
  private func triggerPressed(_ trigger: Trigger, backward: Bool, fromTap: Bool) {
    if fromTap { recordTapTrigger() }
    if snapshot.active {
      dispatchMain { self.handlers.cycle(backward) }
      return
    }
    beginSession(hold: trigger.binding.holdModifiers)
    let mode = trigger.mode
    dispatchMain { self.handlers.summon(mode) }
  }

  /// Hop a main-actor handler onto the main thread, preserving FIFO order.
  private func dispatchMain(_ work: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
  }
}

/// Carries the tap's port into its thread closure (CFMachPort isn't Sendable; after the
/// hand-off only that thread and the lock-guarded `machPort` reference it).
private struct PortBox: @unchecked Sendable {
  let port: CFMachPort
}
