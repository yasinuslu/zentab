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
/// `@unchecked Sendable`: `triggers`/`handlers` are immutable; `active`/`activeHold`
/// are lock-guarded; `machPort`/`runLoop`/`thread` are set once before the tap
/// thread starts.
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
  private static let summonKeyCode: CGKeyCode = 49  // Space
  private static let flingLeftKeyCode: CGKeyCode = 123  // ←
  private static let flingRightKeyCode: CGKeyCode = 124  // →
  private static let escapeKeyCode: CGKeyCode = 53

  private let triggers: [Trigger]
  private let handlers: Handlers

  private let lock = NSLock()
  private var active = false
  /// The held modifiers of the chord that summoned; releasing any of them confirms.
  private var activeHold: NSEvent.ModifierFlags = []

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

    machPort = port
    let thread = Thread { [weak self] in
      // Read the port back through `self` (set before this thread starts) rather
      // than capturing the non-Sendable CFMachPort across the @Sendable boundary.
      guard let self, let port = self.machPort else { return }
      self.lock.lock()
      self.runLoop = CFRunLoopGetCurrent()
      self.lock.unlock()
      let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
      CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
      CGEvent.tapEnable(tap: port, enable: true)
      CFRunLoopRun()
    }
    thread.name = "org.nepjua.ZenTab.hotkey"
    thread.qualityOfService = .userInteractive
    self.thread = thread
    thread.start()
    return true
  }

  func stop() {
    if let machPort { CGEvent.tapEnable(tap: machPort, enable: false) }
    lock.lock()
    let runLoop = self.runLoop
    lock.unlock()
    if let runLoop { CFRunLoopStop(runLoop) }
  }

  /// Is the tap currently delivering events? The OS disables it on secure input and
  /// can time it out; the watchdog polls this so capture health reflects reality.
  /// `machPort` is set once in `start()` before the tap thread runs, so reading it
  /// from the main actor afterwards is safe.
  var isEnabled: Bool {
    guard let machPort else { return false }
    return CGEvent.tapIsEnabled(tap: machPort)
  }

  /// Re-enable the tap if the OS turned it off. Idempotent; cheap to call on a timer.
  /// This is the slow, belt-and-suspenders complement to the in-callback re-enable
  /// (which only fires on the explicit `tapDisabledBy*` events).
  func ensureEnabled() {
    guard let machPort, !CGEvent.tapIsEnabled(tap: machPort) else { return }
    CGEvent.tapEnable(tap: machPort, enable: true)
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
      if let machPort { CGEvent.tapEnable(tap: machPort, enable: true) }
      return passthrough

    case .flagsChanged:
      let (isActive, hold) = snapshot
      guard isActive else { return passthrough }
      let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
      let stillHeld = modifiers.intersection(Keybinding.triggerModifierMask).isSuperset(of: hold)
      if !stillHeld {
        endSession()
        dispatchMain { self.handlers.confirm() }
      }
      return passthrough  // never absorb modifier changes

    case .keyDown:
      let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
      let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
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
      case Self.summonKeyCode:  // Space summons the selected window to this Space
        dispatchMain { self.handlers.summonSelected() }
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
      // Pressing any trigger key again (while held) cycles.
      guard triggers.contains(where: { $0.binding.matches(keyCode: keyCode, modifiers: modifiers) })
      else { return false }
      let backward = modifiers.contains(.shift)
      dispatchMain { self.handlers.cycle(backward) }
      return true
    }

    // Not active: the first matching trigger summons its mode.
    guard
      let trigger = triggers.first(where: {
        $0.binding.matches(keyCode: keyCode, modifiers: modifiers)
      })
    else { return false }
    beginSession(hold: trigger.binding.holdModifiers)
    let mode = trigger.mode
    dispatchMain { self.handlers.summon(mode) }
    return true
  }

  /// Hop a main-actor handler onto the main thread, preserving FIFO order.
  private func dispatchMain(_ work: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
  }
}
