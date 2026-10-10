import AppKit

/// Whether Secure Event Input is on system-wide, and who holds it. While it is on, macOS
/// delivers no key-downs to any event tap (see `SecureInputHotkeys`), so the menu bar
/// says so instead of looking healthy while half the switcher is deaf.
enum SecureInputState: Equatable {
  case off
  case on(holder: String?)

  /// The live state, read from the console session dictionary: the window server
  /// publishes the holder's pid there exactly while secure input is on (what
  /// `ioreg -l | grep SecureInput` shows). Carbon's `IsSecureEventInput` isn't
  /// available to Swift.
  @MainActor
  static var current: SecureInputState {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    guard let pid = (session?["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value, pid > 0
    else { return .off }
    let name = NSRunningApplication(processIdentifier: pid)?.localizedName
    return .on(holder: name ?? "pid \(pid)")
  }
}
