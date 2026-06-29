import AppKit
import CoreGraphics

/// One `CGEventTap` on a dedicated background-thread runloop. It detects the
/// configured trigger chord (summon on first key-down, cycle on subsequent ones),
/// the trigger-modifier *release* (confirm, via `.flagsChanged` — which survives
/// secure input where key events don't), and Esc (cancel). The C tap callback runs
/// on the tap thread and must return its absorb/pass decision synchronously; all
/// actual switcher work is hopped to the main actor.
///
/// `@unchecked Sendable`: `binding`/`handlers` are immutable; `active` is lock-
/// guarded; `machPort`/`runLoop`/`thread` are set once before the tap thread starts.
final class HotkeyTap: @unchecked Sendable {
  /// Main-actor callbacks driven by the tap.
  struct Handlers {
    let summon: @MainActor () -> Void
    let cycle: @MainActor (_ backward: Bool) -> Void
    let confirm: @MainActor () -> Void
    let cancel: @MainActor () -> Void
  }

  private let binding: Keybinding
  private let handlers: Handlers

  private let lock = NSLock()
  private var active = false

  private var machPort: CFMachPort?
  private var runLoop: CFRunLoop?
  private var thread: Thread?

  init(binding: Keybinding, handlers: Handlers) {
    self.binding = binding
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

  // MARK: - Tap-thread state (lock-guarded)

  private var isActive: Bool {
    lock.lock()
    defer { lock.unlock() }
    return active
  }

  private func setActive(_ value: Bool) {
    lock.lock()
    active = value
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
      let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
      let stillHeld = modifiers.intersection(Keybinding.triggerModifierMask)
        .isSuperset(of: binding.holdModifiers)
      if isActive && !stillHeld {
        setActive(false)
        dispatchMain { self.handlers.confirm() }
      }
      return passthrough  // never absorb modifier changes

    case .keyDown:
      let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
      let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))

      // Esc cancels an open switch and is swallowed.
      if isActive && keyCode == 53 {
        setActive(false)
        dispatchMain { self.handlers.cancel() }
        return nil
      }

      if binding.matches(keyCode: keyCode, modifiers: modifiers) {
        let backward = modifiers.contains(.shift)
        if isActive {
          dispatchMain { self.handlers.cycle(backward) }
        } else {
          setActive(true)
          dispatchMain { self.handlers.summon() }
        }
        return nil  // absorb the trigger key so the focused app never sees it
      }
      return passthrough

    default:
      return passthrough
    }
  }

  /// Hop a main-actor handler onto the main thread, preserving FIFO order.
  private func dispatchMain(_ work: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
  }
}
