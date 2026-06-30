import AppKit
import ApplicationServices
import CoreGraphics

/// Thin reads of the two TCC permissions ZenTab needs. Never cache these: macOS
/// 13+ can grant/revoke them while the app runs, and a stale `true` leaves the
/// switcher silently dead. Accessibility is mandatory (the event tap and AX reads
/// need it); Screen Recording only improves thumbnails and is optional for the MVP.
enum Permissions {
  /// Is the process trusted for Accessibility? No prompt.
  static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

  /// Ask for Accessibility, showing the system prompt that deep-links to Settings.
  @discardableResult
  static func requestAccessibility() -> Bool {
    // Key value equals kAXTrustedCheckOptionPrompt ("AXTrustedCheckOptionPrompt");
    // using the literal avoids the Unmanaged<CFString> import ambiguity.
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  /// Whether Screen Recording is granted (governs high-fidelity window capture).
  static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

  @discardableResult
  static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }

  static func openAccessibilitySettings() {
    open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
  }

  static func openScreenRecordingSettings() {
    open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
  }

  private static func open(_ urlString: String) {
    if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
  }
}
