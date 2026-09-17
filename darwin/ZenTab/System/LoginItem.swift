import Foundation
import ServiceManagement

/// ZenTab launches at login, always — it is not a setting.
///
/// An Alt/Cmd+Tab replacement that isn't already resident the moment you reach for the
/// switcher is broken, so per VISION.md ("the default answer to 'should this be a
/// setting?' is no") there is no checkbox: every production launch registers the app as
/// a login item and keeps it registered. Dev builds never register, so a ZenTab running
/// out of DerivedData doesn't quietly add itself to your login items.
///
/// The one thing we can't (and shouldn't) override is an explicit user opt-out in System
/// Settings ▸ General ▸ Login Items: once macOS marks the service `.requiresApproval` we
/// respect it rather than nagging. ZenTab reports the truth instead of fighting the OS —
/// the same honesty as the Cmd+Tab capture watchdog.
enum LoginItem {
  /// Ensure ZenTab is a login item. Idempotent and cheap enough to call on every launch.
  static func ensureRegistered(profile: LaunchProfile) {
    // Only the shipped app auto-starts; a dev build relaunching itself on login would be
    // hostile (wrong chords, wrong build path).
    guard profile == .production else { return }
    // `bin/run-prod` runs the production profile straight out of DerivedData — don't wire a
    // throwaway build path into the user's login items. Only a real installed bundle registers.
    guard !Bundle.main.bundlePath.contains("/DerivedData/") else { return }

    let service = SMAppService.mainApp
    switch service.status {
    case .enabled:
      return  // already on — nothing to do
    case .requiresApproval:
      return  // user turned it off in System Settings; honor that, don't re-nag
    case .notRegistered, .notFound:
      break
    @unknown default:
      break
    }

    do {
      try service.register()
    } catch {
      // Non-fatal: worst case ZenTab just won't auto-start. Surface it for diagnostics
      // rather than crashing the launch.
      NSLog("ZenTab: login-item registration failed: \(error.localizedDescription)")
    }
  }
}
