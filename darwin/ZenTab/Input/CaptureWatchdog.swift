import AppKit
import CoreGraphics

/// Keeps ZenTab's claim on the native Cmd+Tab (and any trigger that collides with a
/// macOS symbolic hotkey) reliable. The Dock consumes those hotkeys *before* our
/// event tap, so we disable them — but defensively:
///
///  - we disable a symbolic hotkey only once the event tap is actually live, so we
///    never brick Cmd+Tab when we can't serve it;
///  - every `tick()` re-asserts the claim (other apps / macOS updates / a login can
///    re-enable them) and re-enables the tap if the OS turned it off;
///  - the moment we genuinely can't capture (Accessibility revoked, tap stuck down)
///    we *restore* the native hotkeys so the user is never stranded with a dead key.
///
/// ZenTab never silently rebinds to a different key as a fallback; `health` reports
/// the truth so the menu bar can show whether we own the shortcut.
@MainActor
final class CaptureWatchdog {
  private let tap: HotkeyTap
  /// Native symbolic hotkeys this binding set must own. Empty for the safe dev
  /// chords, in which case the watchdog only babysits the tap.
  private let managed: Set<SymbolicHotkey>

  private(set) var health: CaptureHealth = .noAccessibility
  /// Fired on the main actor whenever `health` changes (drives the menu bar).
  var onHealthChange: ((CaptureHealth) -> Void)?

  init(tap: HotkeyTap, bindings: [Keybinding]) {
    self.tap = tap
    self.managed = NativeHotkeyConflict.conflicting(with: bindings)
  }

  /// One check-and-repair pass. Cheap and idempotent; safe to call on a short timer
  /// and once immediately after the tap starts (so there's no window where the
  /// native switcher still fires).
  func tick() {
    let next = checkAndRepair()
    guard next != health else { return }
    Log.input.notice("capture health: \(next.summary, privacy: .public)")
    health = next
    onHealthChange?(next)
  }

  /// Rebuild the tap from scratch, then re-check. For moments the system is known to
  /// drop or wedge event taps without telling us (wake from sleep, unlock, display
  /// reconfiguration), where waiting for a symptom would mean a dead shortcut.
  func recover(reason: String) {
    guard Permissions.isAccessibilityTrusted else { return tick() }
    tap.recreate(reason: reason)
    lastRecreate = .now
    tick()
  }

  /// When the watchdog last rebuilt the tap, so a tap that can't be rebuilt (e.g. the
  /// permission is half-revoked) is retried every few seconds rather than every tick.
  private var lastRecreate: Date = .distantPast
  private static let recreateBackoff: TimeInterval = 10

  /// Hand every managed native hotkey back to macOS. Called on graceful quit so
  /// Cmd+Tab works again the moment ZenTab isn't running.
  func release() {
    setManaged(enabled: true)
  }

  // MARK: - Repair

  private func checkAndRepair() -> CaptureHealth {
    guard Permissions.isAccessibilityTrusted else {
      setManaged(enabled: true)  // can't capture — never strand the user
      return .evaluate(accessibilityTrusted: false, tapEnabled: false, stillEnabled: [])
    }

    tap.ensureEnabled()
    // Re-enabling can't revive a dead tap (invalid port, finished thread) or one the
    // system refuses to turn back on: rebuild it.
    if !tap.isEnabled, Date.now.timeIntervalSince(lastRecreate) > Self.recreateBackoff {
      lastRecreate = .now
      tap.recreate(reason: tap.isAlive ? "watchdog: re-enable didn't take" : "watchdog: tap dead")
    }
    guard tap.isEnabled else {
      setManaged(enabled: true)
      return .evaluate(accessibilityTrusted: true, tapEnabled: false, stillEnabled: [])
    }

    // The tap is live: claim the conflicting hotkeys, then verify the claim held.
    setManaged(enabled: false)
    let escaped = managed.filter { CGSIsSymbolicHotKeyEnabled($0.rawValue) }
    return .evaluate(
      accessibilityTrusted: true, tapEnabled: true, stillEnabled: Set(escaped),
      secureInput: .current)
  }

  private func setManaged(enabled: Bool) {
    for hotkey in managed {
      CGSSetSymbolicHotKeyEnabled(hotkey.rawValue, enabled)
    }
  }
}
