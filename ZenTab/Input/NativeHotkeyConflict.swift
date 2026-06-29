import AppKit
import CoreGraphics

/// Pure mapping from configured triggers to the native macOS symbolic hotkeys they
/// collide with. The Dock/WindowServer consumes those hotkeys *before* any event
/// tap, so a trigger that matches one is invisible to ZenTab until it's disabled.
/// No system calls — this is the unit-tested kernel; `CaptureWatchdog` does the IO.
enum NativeHotkeyConflict {
  private static let tab: CGKeyCode = 48
  private static let grave: CGKeyCode = 50

  /// The symbolic hotkeys that must be disabled so `bindings` can be captured.
  static func conflicting(with bindings: [Keybinding]) -> Set<SymbolicHotkey> {
    var result: Set<SymbolicHotkey> = []
    for binding in bindings {
      // Only plain Cmd-based chords collide with the native switchers; the safe dev
      // chords (Ctrl+Opt+…) and Option+Tab match nothing here. Shift is ignored (it
      // is ZenTab's universal "reverse" modifier, never part of a trigger identity).
      guard binding.modifiers.intersection(Keybinding.triggerModifierMask) == [.command]
      else { continue }
      switch binding.keyCode {
      case tab:
        // Owning Cmd+Tab means owning the reverse switcher too, else native
        // Cmd+Shift+Tab still fires while we hold Cmd+Tab (alt-tab issue #5653).
        result.insert(.commandTab)
        result.insert(.commandShiftTab)
      case grave:
        result.insert(.commandKeyAboveTab)
      default:
        break
      }
    }
    return result
  }
}
