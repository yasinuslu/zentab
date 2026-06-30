import Foundation

/// Whether ZenTab is currently, reliably capturing its trigger shortcut. This is the
/// single source of truth the menu bar reflects: ZenTab never silently rebinds to a
/// different key as a fallback — it either captures, or honestly reports that it
/// doesn't and why.
///
/// `evaluate` is the pure classifier (unit-tested); `CaptureWatchdog` gathers the
/// live system facts, performs repairs, then calls it with the post-repair state.
enum CaptureHealth: Equatable {
  /// Tap is live and every conflicting native hotkey is disabled. We own the key.
  case capturing
  /// No Accessibility permission, so the event tap can't run at all.
  case noAccessibility
  /// The tap exists but the OS disabled it (secure-input field, etc.) and it would
  /// not re-enable. Native hotkeys are restored so the user isn't stranded.
  case tapDisabled
  /// Something re-enabled native hotkeys we'd disabled and we couldn't reclaim them.
  case nativeHotkeyEscaped(Set<SymbolicHotkey>)

  /// Classify post-repair system facts. Total over every combination.
  static func evaluate(
    accessibilityTrusted: Bool,
    tapEnabled: Bool,
    stillEnabled: Set<SymbolicHotkey>
  ) -> CaptureHealth {
    if !accessibilityTrusted { return .noAccessibility }
    if !tapEnabled { return .tapDisabled }
    if !stillEnabled.isEmpty { return .nativeHotkeyEscaped(stillEnabled) }
    return .capturing
  }

  var isCapturing: Bool { self == .capturing }

  /// SF Symbol for the menu bar item: a calm rectangle when we own the shortcut, a
  /// warning triangle the instant we don't.
  var menuBarSymbol: String {
    isCapturing ? "rectangle.on.rectangle" : "exclamationmark.triangle.fill"
  }

  /// One-line status shown in the menu bar dropdown.
  var summary: String {
    switch self {
    case .capturing:
      return "Capturing the shortcut"
    case .noAccessibility:
      return "Not capturing — Accessibility permission needed"
    case .tapDisabled:
      return "Not capturing — input is temporarily blocked (secure field?)"
    case .nativeHotkeyEscaped:
      return "Not capturing — macOS reclaimed the shortcut; retrying"
    }
  }
}
