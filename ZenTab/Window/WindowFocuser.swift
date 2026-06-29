import ApplicationServices
import CoreGraphics

/// Brings an arbitrary window of another app to the front *and* makes it key.
///
/// No single public API does this on macOS 14/15: `_SLPSSetFrontProcessWithOptions`
/// fronts the process + window but doesn't make it key; `kAXRaiseAction` only
/// reorders within the app's own stack; `NSRunningApplication.activate` is advisory
/// since macOS 14. So we run the strict private sequence used by yabai / alt-tab:
///
///   de-minimize -> front (SLPS, 0x200) -> make key (synthetic click) -> AX raise
///
/// All of it runs off the main thread (AX calls block; posting WindowServer events
/// from main can stall the UI). `WindowInfo` holds no AX handle, so we re-derive the
/// AX window element from (pid, windowID) here.
enum WindowFocuser {
  private static let queue = DispatchQueue(label: "org.nepjua.ZenTab.focus", qos: .userInteractive)

  static func focus(_ window: WindowInfo) {
    let pid = window.pid
    let windowID = window.windowID
    queue.async { perform(pid: pid, windowID: windowID) }
  }

  private static func perform(pid: pid_t, windowID: CGWindowID) {
    let axWindow = findAXWindow(pid: pid, windowID: windowID)

    // Pre-step: de-minimize, or there is no on-screen window to front/key/raise.
    if let axWindow {
      AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }

    // pid -> ProcessSerialNumber (the SLPS calls take a PSN, not a pid).
    var psn = ProcessSerialNumber()
    guard zt_GetProcessForPID(pid, &psn) == noErr else { return }

    // 1. FRONT the process and bring just this window forward (0x200 = user-generated).
    _SLPSSetFrontProcessWithOptions(&psn, windowID, SLPSMode.userGenerated.rawValue)

    // 2. MAKE KEY via a synthetic left mouse-down/up pair aimed off the content.
    makeKeyWindow(&psn, windowID)

    // 3. RAISE within the app's own window stack.
    if let axWindow {
      AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
    }
  }

  /// Find the app's AX window element whose CGWindowID matches.
  private static func findAXWindow(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
    let axApp = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
      let windows = value as? [AXUIElement]
    else { return nil }
    for axWindow in windows {
      var candidate: CGWindowID = 0
      if _AXUIElementGetWindow(axWindow, &candidate) == .success, candidate == windowID {
        return axWindow
      }
    }
    return nil
  }

  /// Post the synthetic click pair that makes `windowID` the key window of `psn`.
  ///
  /// The CGSEventRecord byte layout is the documented offset table from
  /// yabai / CGSInternal (no GPL code copied — these are reverse-engineered offsets):
  ///   - buffer is 0x100 bytes, zeroed (a 0xf8 buffer SIGABRTs on macOS 14.7.4+,
  ///     because CGSEncodeEventRecord reads past the 0xf8 record)
  ///   - 0x04 = record length (0xf8)
  ///   - 0x08 = event type (0x01 left-mouse-down, then 0x02 left-mouse-up)
  ///   - 0x20 = 0x10 bytes of 0xFF: a location off any real content
  ///   - 0x3a = 0x10
  ///   - 0x3c = the target window id (UInt32)
  private static func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ windowID: CGWindowID) {
    func post(eventType: UInt8) {
      var bytes = [UInt8](repeating: 0, count: 0x100)
      bytes[0x04] = 0xf8
      bytes[0x08] = eventType
      bytes[0x3a] = 0x10
      for index in 0..<0x10 { bytes[0x20 + index] = 0xFF }
      var id = windowID
      withUnsafeBytes(of: &id) { source in
        for index in 0..<4 { bytes[0x3c + index] = source[index] }
      }
      bytes.withUnsafeMutableBufferPointer { buffer in
        _ = SLPSPostEventRecordTo(&psn, buffer.baseAddress!)
      }
    }
    post(eventType: 0x01)
    post(eventType: 0x02)
  }
}
