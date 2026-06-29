import AppKit
import ApplicationServices

/// Brings an arbitrary window of another app to the front *and* makes it key,
/// including across Spaces.
///
/// No single public API does this on macOS 14/15, so we run the exact private
/// sequence alt-tab/yabai use:
///
///   de-minimize -> front (SLPS, 0x200) -> make key (synthetic click) -> AX raise
///   -> (cross-Space) restore the origin Space's previous front
///
/// `_SLPSSetFrontProcessWithOptions` with the window id switches to a Space showing
/// the window. The cross-Space front-switch makes the *origin* Space remember our
/// app as its front (#4507); we repair that afterward so going back shows what was
/// there before. All of it runs off the main thread (AX calls block; posting
/// WindowServer events from main can stall the UI). `WindowInfo` holds no AX handle,
/// so we re-derive the AX window from (pid, windowID) here.
enum WindowFocuser {
  private static let queue = DispatchQueue(label: "org.nepjua.ZenTab.focus", qos: .userInteractive)

  static func focus(_ window: WindowInfo) {
    // Snapshot main-only state before going off-main.
    let pid = window.pid
    let windowID = window.windowID
    let isMinimized = window.isMinimized
    let originFrontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    // Keep this a String (Sendable) across the queue hop; bridge back to CFString inside.
    let mainScreenUUID = NSScreen.main?.spaceUUID()
    queue.async {
      perform(
        pid: pid, windowID: windowID, isMinimized: isMinimized,
        originFrontPID: originFrontPID, mainScreenUUID: mainScreenUUID)
    }
  }

  private static func perform(
    pid: pid_t, windowID: CGWindowID, isMinimized: Bool,
    originFrontPID: pid_t?, mainScreenUUID: String?
  ) {
    let axWindow = findAXWindow(pid: pid, windowID: windowID)

    // Is the target on the current Space? (Drives the origin-Space repair below.)
    let originSpaceID = mainScreenUUID.map {
      CGSManagedDisplayGetCurrentSpace(cgsConnection, $0 as CFString)
    }
    let windowSpaces =
      (CGSCopySpacesForWindows(cgsConnection, CGSSpaceMask.all.rawValue, [windowID] as CFArray)
        as? [CGSSpaceID]) ?? []
    let targetOnCurrentSpace = originSpaceID.map { windowSpaces.contains($0) } ?? true

    // Pre-step: de-minimize, or there is no on-screen window to front/key/raise.
    if isMinimized, let axWindow {
      AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }

    // pid -> ProcessSerialNumber (the SLPS calls take a PSN, not a pid).
    var psn = ProcessSerialNumber()
    guard zt_GetProcessForPID(pid, &psn) == noErr else { return }

    // 1. FRONT the process and bring just this window forward (0x200 = user-generated).
    //    For a cross-Space target this also switches to a Space showing it.
    _SLPSSetFrontProcessWithOptions(&psn, windowID, SLPSMode.userGenerated.rawValue)

    // 2. MAKE KEY via a synthetic left mouse-down/up pair aimed off the content.
    makeKeyWindow(&psn, windowID)

    // 3. RAISE within the app's own window stack.
    if let axWindow {
      AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
    }

    // 4. CROSS-SPACE repair: undo step 1's clobber of the origin Space's front.
    if !targetOnCurrentSpace, let originSpaceID, let originFrontPID, originFrontPID != pid {
      var originPSN = ProcessSerialNumber()
      if zt_GetProcessForPID(originFrontPID, &originPSN) == noErr {
        SLSSpaceSetFrontPSN(cgsConnection, originSpaceID, originPSN)
      }
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
  /// yabai / CGSInternal: a 0x100-byte zeroed buffer (a 0xf8 buffer SIGABRTs on
  /// macOS 14.7.4+); 0x04 = record length 0xf8; 0x08 = event type (0x01 down, 0x02
  /// up); 0x20 = a 16-byte window-relative CGPoint aimed just off the content at
  /// (-1, -1) so it hit-tests to no view (a "wild" value risks being clamped onto
  /// real content); 0x3a = 0x10; 0x3c = the target window id.
  private static func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ windowID: CGWindowID) {
    func post(eventType: UInt8) {
      var bytes = [UInt8](repeating: 0, count: 0x100)
      bytes[0x04] = 0xf8
      bytes[0x08] = eventType
      bytes[0x3a] = 0x10
      var id = windowID
      withUnsafeBytes(of: &id) { source in
        for index in 0..<MemoryLayout<CGWindowID>.size { bytes[0x3c + index] = source[index] }
      }
      var point = CGPoint(x: -1, y: -1)
      withUnsafeBytes(of: &point) { source in
        for index in 0..<MemoryLayout<CGPoint>.size { bytes[0x20 + index] = source[index] }
      }
      bytes.withUnsafeMutableBufferPointer { buffer in
        _ = SLPSPostEventRecordTo(&psn, buffer.baseAddress!)
      }
    }
    post(eventType: 0x01)
    post(eventType: 0x02)
  }
}

extension NSScreen {
  /// The display's WindowServer UUID string, for CGS Space queries. Returned as a
  /// `String` so it can cross a concurrency boundary (CFString isn't Sendable).
  func spaceUUID() -> String? {
    guard
      let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
      let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue()
    else { return nil }
    return CFUUIDCreateString(nil, uuid) as String
  }
}
