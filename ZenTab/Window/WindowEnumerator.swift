import AppKit
import ApplicationServices

/// Builds the actionable window list off the main thread and returns `Sendable`
/// `WindowInfo` values. Strategy for the MVP "other apps" mode:
///
/// - **CoreGraphics window list** (public, thread-safe) gives global front-to-back
///   z-order, window id, owner pid, owner name, bounds, and current-Space/on-screen
///   filtering for free (`.optionOnScreenOnly`). This drives ordering and identity.
/// - **Accessibility** enriches each window with its subrole, minimized flag, and a
///   reliable title (works without Screen Recording), and is the bridge we'll reuse
///   at focus time. AX calls can block, so the whole thing runs off-main.
enum WindowEnumerator {
  /// Switchable windows of every app except those in `excluded` (the current app
  /// and ZenTab itself), in global front-to-back order.
  static func enumerate(excludingPIDs excluded: Set<pid_t>) async -> [WindowInfo] {
    await withCheckedContinuation { continuation in
      queue.async { continuation.resume(returning: collect(excluding: excluded)) }
    }
  }

  private static let queue = DispatchQueue(
    label: "org.nepjua.ZenTab.enumeration", qos: .userInteractive)

  /// One on-screen window from the CoreGraphics list: ordering + identity + bounds.
  private struct Entry {
    let windowID: CGWindowID
    let pid: pid_t
    let ownerName: String
    let bounds: CGRect
    let cgTitle: String
  }

  /// The Accessibility enrichment for a window.
  private struct AXDetail {
    let subrole: String
    let minimized: Bool
    let title: String
  }

  private static func collect(excluding excluded: Set<pid_t>) -> [WindowInfo] {
    let entries = onScreenEntries(excluding: excluded)
    let details = axDetails(for: Set(entries.map(\.pid)))
    return entries.compactMap { entry in
      let window = merge(entry, details[entry.windowID])
      return WindowInfo.isSwitchable(window) ? window : nil
    }
  }

  /// Normal windows (layer 0) of non-excluded apps, in the CoreGraphics
  /// front-to-back z-order.
  private static func onScreenEntries(excluding excluded: Set<pid_t>) -> [Entry] {
    guard
      let infoList = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return [] }

    var entries: [Entry] = []
    for info in infoList {
      guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
        let windowID = info[kCGWindowNumber as String] as? CGWindowID,
        let pid = info[kCGWindowOwnerPID as String] as? pid_t,
        !excluded.contains(pid)
      else { continue }
      entries.append(
        Entry(
          windowID: windowID,
          pid: pid,
          ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
          bounds: boundsRect(info[kCGWindowBounds as String]),
          cgTitle: info[kCGWindowName as String] as? String ?? ""))
    }
    return entries
  }

  /// Accessibility detail per window id, gathered once per app.
  private static func axDetails(for pids: Set<pid_t>) -> [CGWindowID: AXDetail] {
    var details: [CGWindowID: AXDetail] = [:]
    for pid in pids {
      let axApp = AXUIElementCreateApplication(pid)
      guard let axWindows = copyAttribute(axApp, kAXWindowsAttribute) as? [AXUIElement] else {
        continue
      }
      for axWindow in axWindows {
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(axWindow, &windowID) == .success, windowID != 0 else {
          continue
        }
        details[windowID] = AXDetail(
          subrole: copyAttribute(axWindow, kAXSubroleAttribute) as? String ?? "",
          minimized: (copyAttribute(axWindow, kAXMinimizedAttribute) as? Bool) ?? false,
          title: copyAttribute(axWindow, kAXTitleAttribute) as? String ?? "")
      }
    }
    return details
  }

  private static func merge(_ entry: Entry, _ detail: AXDetail?) -> WindowInfo {
    // If AX is silent for this window, assume a standard window so a missing detail
    // doesn't drop an otherwise-valid entry.
    let subrole = detail?.subrole.isEmpty == false ? detail!.subrole : "AXStandardWindow"
    let axTitle = detail?.title ?? ""
    return WindowInfo(
      pid: entry.pid,
      windowID: entry.windowID,
      title: axTitle.isEmpty ? entry.cgTitle : axTitle,
      appName: entry.ownerName,
      frame: entry.bounds,
      isMinimized: detail?.minimized ?? false,
      subrole: subrole)
  }

  private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
      return nil
    }
    return value
  }

  private static func boundsRect(_ value: Any?) -> CGRect {
    guard let dictionary = value as? NSDictionary,
      let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    else { return .zero }
    return rect
  }
}
