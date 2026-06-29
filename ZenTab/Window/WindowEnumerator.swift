import AppKit
import ApplicationServices

/// Builds the actionable window list off the main thread and returns `Sendable`
/// `WindowInfo` values, fresh on every summon (no caching — so it always reflects
/// the current state, e.g. a window just moved to another Space).
///
/// Reliability comes from **unioning every discovery source** rather than trusting
/// one:
/// - `CGWindowList(.optionOnScreenOnly)` — current-Space windows in true front-to-back
///   z-order (drives ordering).
/// - `CGWindowList` without that flag — every window the WindowServer knows about,
///   including other Spaces (the `everything` mode).
/// - Accessibility per app — minimized windows, plus subrole/title enrichment.
///
/// A window is included if *any* source has it. The current-app / other-apps modes
/// stay scoped to the current Space (per VISION); only `everything` reaches across
/// Spaces and includes minimized windows.
enum WindowEnumerator {
  /// `monitorFrame` (CoreGraphics coords) restricts the scoped modes to one monitor;
  /// pass nil to span all monitors (the `everything` mode always spans all).
  static func enumerate(
    mode: SwitchMode, frontmostPID: pid_t?, selfPID: pid_t, monitorFrame: CGRect?
  ) async -> [WindowInfo] {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(
          returning: collect(
            mode: mode, frontmostPID: frontmostPID, selfPID: selfPID, monitorFrame: monitorFrame))
      }
    }
  }

  private static let queue = DispatchQueue(
    label: "org.nepjua.ZenTab.enumeration", qos: .userInteractive)

  /// One window from the CoreGraphics list: identity + owner + bounds.
  private struct Entry {
    let windowID: CGWindowID
    let pid: pid_t
    let ownerName: String
    let bounds: CGRect
    let cgTitle: String
  }

  /// Accessibility detail for a window.
  private struct AXDetail {
    let pid: pid_t
    let appName: String
    let subrole: String
    let minimized: Bool
    let title: String
    let frame: CGRect
  }

  // MARK: - Collection

  private static func collect(
    mode: SwitchMode, frontmostPID: pid_t?, selfPID: pid_t, monitorFrame: CGRect?
  ) -> [WindowInfo] {
    switch mode {
    case .everything:
      return collectEverything(selfPID: selfPID)
    case .currentApp, .otherApps:
      return collectCurrentSpace(
        mode: mode, frontmostPID: frontmostPID, selfPID: selfPID, monitorFrame: monitorFrame)
    }
  }

  /// Current-Space, current-monitor, on-screen windows for the scoped modes.
  private static func collectCurrentSpace(
    mode: SwitchMode, frontmostPID: pid_t?, selfPID: pid_t, monitorFrame: CGRect?
  ) -> [WindowInfo] {
    let include: (pid_t) -> Bool = {
      includes($0, mode: mode, frontmostPID: frontmostPID, selfPID: selfPID)
    }
    let entries = windowEntries(onScreenOnly: true, include: include)
    let details = axDetails(for: Set(entries.map(\.pid)))
    return entries.map { merge($0, details[$0.windowID]) }
      .filter { WindowInfo.isSwitchable($0) && $0.isOnMonitor(monitorFrame) }
  }

  /// Every window across all Spaces (plus minimized), for the `everything` mode.
  private static func collectEverything(selfPID: pid_t) -> [WindowInfo] {
    let candidates = candidatePIDs(selfPID: selfPID)
    let include: (pid_t) -> Bool = { candidates.contains($0) }

    let allWindows = windowEntries(onScreenOnly: false, include: include)
    let details = axDetails(for: candidates)
    let zOrder = onScreenZOrder(include: include)

    // Union by window id: CoreGraphics first (accurate bounds + identity), then any
    // AX-only window the WindowServer list missed (e.g. minimized).
    var byID: [CGWindowID: WindowInfo] = [:]
    for entry in allWindows { byID[entry.windowID] = merge(entry, details[entry.windowID]) }
    for (windowID, detail) in details where byID[windowID] == nil {
      byID[windowID] = windowFromAX(windowID: windowID, detail: detail)
    }

    let switchable = byID.values.filter { WindowInfo.isSwitchable($0, includeMinimized: true) }
    // On-screen (current Space) first in z-order, then the rest grouped stably by app.
    let onScreen =
      switchable
      .filter { zOrder[$0.windowID] != nil }
      .sorted { zOrder[$0.windowID]! < zOrder[$1.windowID]! }
    let elsewhere =
      switchable
      .filter { zOrder[$0.windowID] == nil }
      .sorted { ($0.appName, $0.windowID) < ($1.appName, $1.windowID) }
    return onScreen + elsewhere
  }

  // MARK: - Sources

  private static func includes(
    _ pid: pid_t, mode: SwitchMode, frontmostPID: pid_t?, selfPID: pid_t
  ) -> Bool {
    guard pid != selfPID else { return false }
    switch mode {
    // otherApps includes the current app too (its windows are in the list); the
    // selection just starts past the focused window so a quick tap still switches
    // away. currentApp is the only mode that filters to a single app.
    case .everything, .otherApps: return true
    case .currentApp: return pid == frontmostPID
    }
  }

  /// pids of all regular apps except ZenTab itself.
  private static func candidatePIDs(selfPID: pid_t) -> Set<pid_t> {
    var pids = Set<pid_t>()
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
      let pid = app.processIdentifier
      if pid != selfPID { pids.insert(pid) }
    }
    return pids
  }

  /// Layer-0 windows from CoreGraphics, optionally restricted to the current Space.
  private static func windowEntries(onScreenOnly: Bool, include: (pid_t) -> Bool) -> [Entry] {
    var options: CGWindowListOption = [.excludeDesktopElements]
    if onScreenOnly { options.insert(.optionOnScreenOnly) }
    guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else { return [] }

    var entries: [Entry] = []
    for info in infoList {
      guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
        let windowID = info[kCGWindowNumber as String] as? CGWindowID,
        let pid = info[kCGWindowOwnerPID as String] as? pid_t, include(pid)
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

  /// Current-Space z-order index per window id.
  private static func onScreenZOrder(include: (pid_t) -> Bool) -> [CGWindowID: Int] {
    var order: [CGWindowID: Int] = [:]
    for (index, entry) in windowEntries(onScreenOnly: true, include: include).enumerated() {
      order[entry.windowID] = index
    }
    return order
  }

  /// Accessibility detail per window id, gathered once per app (covers all Spaces
  /// and minimized windows the app exposes).
  private static func axDetails(for pids: Set<pid_t>) -> [CGWindowID: AXDetail] {
    var details: [CGWindowID: AXDetail] = [:]
    for pid in pids {
      let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
      let axApp = AXUIElementCreateApplication(pid)
      guard let axWindows = copyAttribute(axApp, kAXWindowsAttribute) as? [AXUIElement] else {
        continue
      }
      for axWindow in axWindows {
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(axWindow, &windowID) == .success, windowID != 0 else {
          continue
        }
        let origin = axPoint(axWindow, kAXPositionAttribute) ?? .zero
        let size = axSize(axWindow, kAXSizeAttribute) ?? .zero
        details[windowID] = AXDetail(
          pid: pid,
          appName: appName,
          subrole: copyAttribute(axWindow, kAXSubroleAttribute) as? String ?? "",
          minimized: (copyAttribute(axWindow, kAXMinimizedAttribute) as? Bool) ?? false,
          title: copyAttribute(axWindow, kAXTitleAttribute) as? String ?? "",
          frame: CGRect(origin: origin, size: size))
      }
    }
    return details
  }

  // MARK: - Building WindowInfo

  private static func merge(_ entry: Entry, _ detail: AXDetail?) -> WindowInfo {
    let axTitle = detail?.title ?? ""
    return WindowInfo(
      pid: entry.pid,
      windowID: entry.windowID,
      title: axTitle.isEmpty ? entry.cgTitle : axTitle,
      appName: entry.ownerName,
      frame: entry.bounds,
      isMinimized: detail?.minimized ?? false,
      subrole: detail?.subrole ?? "")
  }

  private static func windowFromAX(windowID: CGWindowID, detail: AXDetail) -> WindowInfo {
    WindowInfo(
      pid: detail.pid,
      windowID: windowID,
      title: detail.title.isEmpty ? detail.appName : detail.title,
      appName: detail.appName,
      frame: detail.frame,
      isMinimized: detail.minimized,
      subrole: detail.subrole)
  }

  // MARK: - AX value helpers

  private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
      return nil
    }
    return value
  }

  private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
    guard let value = copyAttribute(element, attribute), CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    // Safe: guarded by the AXValue type-id check above.
    // swiftlint:disable:next force_cast
    return (value as! AXValue)
  }

  private static func axPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    guard let value = axValue(element, attribute) else { return nil }
    var point = CGPoint.zero
    return AXValueGetValue(value, .cgPoint, &point) ? point : nil
  }

  private static func axSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    guard let value = axValue(element, attribute) else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(value, .cgSize, &size) ? size : nil
  }

  private static func boundsRect(_ value: Any?) -> CGRect {
    guard let dictionary = value as? NSDictionary,
      let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    else { return .zero }
    return rect
  }
}
