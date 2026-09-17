import AppKit
import Carbon.HIToolbox

/// Registers the trigger chords as Carbon hot keys, the fallback that keeps the shortcut
/// alive under **Secure Event Input**. While a password field is focused (or a terminal's
/// secure keyboard entry is on), macOS stops delivering key-downs to every event tap —
/// only `.flagsChanged` survives. ZenTab has disabled the native Cmd+Tab, so without
/// this the shortcut would silently do nothing until secure input ends. Registered hot
/// keys are still delivered then (the same approach alt-tab takes).
///
/// The tap stays the primary path (it also owns release-to-confirm and the in-overlay
/// keys); every press lands in `HotkeyTap.fallbackTriggerPressed`, which drops the echo
/// of a press the tap already handled. Each binding is registered twice — plain (cycle
/// forward) and with Shift (backward) — because Carbon matches modifiers exactly.
@MainActor
final class SecureInputHotkeys {
  private static let signature: OSType = 0x5A54_6162  // "ZTab"

  private let bindings: [Keybinding]
  private let onPress: (_ index: Int, _ backward: Bool) -> Void
  private var hotKeys: [EventHotKeyRef] = []
  private var handler: EventHandlerRef?

  init(bindings: [Keybinding], onPress: @escaping (_ index: Int, _ backward: Bool) -> Void) {
    self.bindings = bindings
    self.onPress = onPress
  }

  func start() {
    guard handler == nil else { return }
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetEventDispatcherTarget(), Self.callback, 1, &spec,
      Unmanaged.passUnretained(self).toOpaque(), &handler)

    for (index, binding) in bindings.enumerated() {
      let base = Self.carbonModifiers(binding.holdModifiers)
      for backward in [false, true] {
        // id = index·2 + direction, decoded in `pressed`.
        let id = EventHotKeyID(signature: Self.signature, id: UInt32(index * 2 + (backward ? 1 : 0)))
        var ref: EventHotKeyRef?
        let modifiers = backward ? base | UInt32(shiftKey) : base
        let status = RegisterEventHotKey(
          UInt32(binding.keyCode), modifiers, id, GetEventDispatcherTarget(), 0, &ref)
        // A duplicate chord (two modes bound alike) fails to register; the first wins,
        // matching the tap's first-match rule.
        if status == noErr, let ref { hotKeys.append(ref) }
      }
    }
  }

  func stop() {
    for ref in hotKeys { UnregisterEventHotKey(ref) }
    hotKeys = []
    if let handler { RemoveEventHandler(handler) }
    handler = nil
  }

  private func pressed(_ id: UInt32) {
    onPress(Int(id / 2), id % 2 == 1)
  }

  private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var result: UInt32 = 0
    if flags.contains(.command) { result |= UInt32(cmdKey) }
    if flags.contains(.option) { result |= UInt32(optionKey) }
    if flags.contains(.control) { result |= UInt32(controlKey) }
    return result
  }

  /// Non-capturing, so it converts to the C `EventHandlerUPP`. Carbon dispatches hot-key
  /// events on the main thread's event loop.
  private static let callback: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
      event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
      MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr, id.signature == SecureInputHotkeys.signature else {
      return OSStatus(eventNotHandledErr)
    }
    let hotkeys = Unmanaged<SecureInputHotkeys>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { hotkeys.pressed(id.id) }
    return noErr
  }
}
