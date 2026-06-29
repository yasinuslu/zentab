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
    let role: String
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
    let details = axDetails(for: Set(entries.map(\.pid)), bruteForce: false)
    return entries.map { merge($0, details[$0.windowID]) }
      .filter { WindowInfo.isSwitchable($0) && $0.isOnMonitor(monitorFrame) }
  }

  /// Every window across all Spaces (plus minimized), for the `everything` mode.
  ///
  /// **AX-primary:** the list is the set of real Accessibility windows (current-Space
  /// via `kAXWindowsAttribute`, other Spaces via brute-force), keyed by window id.
  /// CoreGraphics only *enriches* (accurate bounds, owner name) and *orders* (z-order);
  /// it never contributes a window on its own. That is the whole fix: a CG-only entry
  /// with no AX window behind it — Finder's desktop, an app's off-screen helper, a
  /// phantom — has nothing we could focus, so it must not appear (the switchability
  /// principle). Other-Space windows now carry a real AX window + correct id, so they
  /// are both shown once (no duplicates) and focusable.
  private static func collectEverything(selfPID: pid_t) -> [WindowInfo] {
    let candidates = candidatePIDs(selfPID: selfPID)
    let include: (pid_t) -> Bool = { candidates.contains($0) }

    let details = axDetails(for: candidates, bruteForce: true)
    let cg = Dictionary(
      windowEntries(onScreenOnly: false, include: include).map { ($0.windowID, $0) },
      uniquingKeysWith: { first, _ in first })
    let zOrder = onScreenZOrder(include: include)

    let infos = details.map { windowID, detail -> WindowInfo in
      let entry = cg[windowID]
      let bounds = entry.map { $0.bounds == .zero ? detail.frame : $0.bounds } ?? detail.frame
      let axTitle = detail.title
      let title = axTitle.isEmpty ? (entry?.cgTitle ?? "") : axTitle
      return WindowInfo(
        pid: detail.pid,
        windowID: windowID,
        title: title.isEmpty ? detail.appName : title,
        appName: entry.map { $0.ownerName.isEmpty ? detail.appName : $0.ownerName } ?? detail.appName,
        frame: bounds,
        isMinimized: detail.minimized,
        subrole: detail.subrole)
    }

    let switchable = infos.filter { WindowInfo.isSwitchable($0, includeMinimized: true) }
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

  /// Accessibility detail per window id, gathered once per app. `bruteForce` adds the
  /// other-Space windows that `kAXWindowsAttribute` omits — the `everything` mode needs
  /// them; the current-Space scoped modes don't, so they skip the cost.
  private static func axDetails(for pids: Set<pid_t>, bruteForce: Bool) -> [CGWindowID: AXDetail] {
    var details: [CGWindowID: AXDetail] = [:]
    for pid in pids {
      let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
      let axApp = AXUIElementCreateApplication(pid)
      // kAXWindowsAttribute is current-Space only; brute-force fills in other Spaces.
      // Attribute windows come first so their (accurate) detail wins on any overlap.
      var axWindows = (copyAttribute(axApp, kAXWindowsAttribute) as? [AXUIElement]) ?? []
      if bruteForce { axWindows += bruteForceAXWindows(pid: pid) }
      for axWindow in axWindows {
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(axWindow, &windowID) == .success, windowID != 0,
          details[windowID] == nil
        else { continue }
        let origin = axPoint(axWindow, kAXPositionAttribute) ?? .zero
        let size = axSize(axWindow, kAXSizeAttribute) ?? .zero
        details[windowID] = AXDetail(
          pid: pid,
          appName: appName,
          role: copyAttribute(axWindow, kAXRoleAttribute) as? String ?? "",
          subrole: copyAttribute(axWindow, kAXSubroleAttribute) as? String ?? "",
          minimized: (copyAttribute(axWindow, kAXMinimizedAttribute) as? Bool) ?? false,
          title: copyAttribute(axWindow, kAXTitleAttribute) as? String ?? "",
          frame: CGRect(origin: origin, size: size))
      }
    }
    return details
  }

  /// Other-Space windows of `pid`, found by reconstructing AX elements from their
  /// "remote tokens" (which `kAXWindowsAttribute` doesn't return). The token is a
  /// 20-byte blob: pid (4) · 0 (4) · 0x636f636f (4) · an `AXUIElementID` (8); we
  /// iterate the trailing id. Bounded to 1000 ids / 100ms per app (alt-tab's
  /// tradeoff) and filtered to real window subroles, so phantoms never enter.
  private static func bruteForceAXWindows(pid: pid_t) -> [AXUIElement] {
    var token = Data(count: 20)  // zero-filled: bytes [4,8) stay 0
    withUnsafeBytes(of: pid) { token.replaceSubrange(0..<4, with: $0) }
    withUnsafeBytes(of: Int32(0x636f_636f)) { token.replaceSubrange(8..<12, with: $0) }

    var windows: [AXUIElement] = []
    let deadline = DispatchTime.now().uptimeNanoseconds + 100_000_000  // 100ms budget
    for elementID in UInt64(0)..<1000 {
      withUnsafeBytes(of: elementID) { token.replaceSubrange(12..<20, with: $0) }
      if let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() {
        let subrole = copyAttribute(element, kAXSubroleAttribute) as? String ?? ""
        if subrole == "AXStandardWindow" || subrole == "AXDialog" { windows.append(element) }
      }
      if DispatchTime.now().uptimeNanoseconds > deadline { break }
    }
    return windows
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

  // MARK: - Switchability diagnostic (read-only)

  /// One everything-mode *candidate* window with every signal we have, captured
  /// BEFORE any switchability filtering. The menu's "Dump switchability" action
  /// writes these to a file so we can see exactly why a window is or isn't
  /// switchable. This is the permanent instrument for evolving
  /// `WindowInfo.isSwitchable` as we learn new focus tricks (the principle:
  /// only show windows we can actually switch to).
  struct SwitchabilityProbe: Sendable {
    let appName: String
    let title: String
    let pid: pid_t
    let windowID: CGWindowID
    /// `kCGWindowLayer` (window level). nil when the window is AX-only (CG missed it).
    let cgLayer: Int?
    /// In the current-Space on-screen CG list.
    let onScreen: Bool
    /// CGS reports it living on the active Space.
    let onCurrentSpace: Bool
    /// An AX window element with this id was resolvable (what the focus raise needs).
    let hasAXWindow: Bool
    let role: String
    let subrole: String
    let minimized: Bool
    let width: CGFloat
    let height: CGFloat
    /// Would today's everything-mode list include it.
    let passesCurrentFilter: Bool
  }

  /// Raw CG window read for diagnostics: ALL layers (no `layer == 0` gate), so we
  /// can see chrome/helper levels too.
  private struct RawCG {
    let windowID: CGWindowID
    let pid: pid_t
    let ownerName: String
    let bounds: CGRect
    let cgTitle: String
    let layer: Int
  }

  static func probeEverything(
    selfPID: pid_t, mainScreenUUID: String?
  ) async -> [SwitchabilityProbe] {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(
          returning: collectProbes(selfPID: selfPID, mainScreenUUID: mainScreenUUID))
      }
    }
  }

  private static func collectProbes(
    selfPID: pid_t, mainScreenUUID: String?
  ) -> [SwitchabilityProbe] {
    let candidates = candidatePIDs(selfPID: selfPID)
    let include: (pid_t) -> Bool = { candidates.contains($0) }

    let cgAll = rawCGWindows(onScreenOnly: false, include: include)
    let onScreenIDs = Set(rawCGWindows(onScreenOnly: true, include: include).map(\.windowID))
    let ax = axDetails(for: candidates, bruteForce: true)
    let cgByID = Dictionary(cgAll.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })

    let currentSpace = mainScreenUUID.map {
      CGSManagedDisplayGetCurrentSpace(cgsConnection, $0 as CFString)
    }

    var ids = Set(cgAll.map(\.windowID))
    ids.formUnion(ax.keys)

    var probes: [SwitchabilityProbe] = []
    for windowID in ids {
      let cg = cgByID[windowID]
      let detail = ax[windowID]
      let pid = detail?.pid ?? cg?.pid ?? 0
      let appName = (detail.map { $0.appName.isEmpty ? nil : $0.appName } ?? nil) ?? cg?.ownerName ?? ""
      let axTitle = detail?.title ?? ""
      let title = axTitle.isEmpty ? (cg?.cgTitle ?? "") : axTitle
      let frame = detail?.frame ?? cg?.bounds ?? .zero

      // Replicate the merged WindowInfo the production path would build, plus the
      // layer-0 gate the everything-mode CG branch applies, to record whether the
      // window is shown today.
      let merged = WindowInfo(
        pid: pid, windowID: windowID, title: title, appName: appName, frame: frame,
        isMinimized: detail?.minimized ?? false, subrole: detail?.subrole ?? "")
      let layerOK = cg.map { $0.layer == 0 } ?? true  // AX-only windows skip the CG layer gate
      let passes = WindowInfo.isSwitchable(merged, includeMinimized: true) && layerOK

      let onCurrentSpace: Bool = {
        guard let currentSpace else { return false }
        let spaces =
          (CGSCopySpacesForWindows(
            cgsConnection, CGSSpaceMask.all.rawValue, [windowID] as CFArray) as? [CGSSpaceID]) ?? []
        return spaces.contains(currentSpace)
      }()

      probes.append(
        SwitchabilityProbe(
          appName: appName, title: title, pid: pid, windowID: windowID,
          cgLayer: cg?.layer, onScreen: onScreenIDs.contains(windowID),
          onCurrentSpace: onCurrentSpace, hasAXWindow: detail != nil,
          role: detail?.role ?? "", subrole: detail?.subrole ?? "",
          minimized: detail?.minimized ?? false,
          width: frame.width, height: frame.height, passesCurrentFilter: passes))
    }
    return probes.sorted { ($0.appName.lowercased(), $0.title) < ($1.appName.lowercased(), $1.title) }
  }

  private static func rawCGWindows(onScreenOnly: Bool, include: (pid_t) -> Bool) -> [RawCG] {
    var options: CGWindowListOption = [.excludeDesktopElements]
    if onScreenOnly { options.insert(.optionOnScreenOnly) }
    guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else { return [] }
    var out: [RawCG] = []
    for info in infoList {
      guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
        let pid = info[kCGWindowOwnerPID as String] as? pid_t, include(pid)
      else { continue }
      out.append(
        RawCG(
          windowID: windowID, pid: pid,
          ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
          bounds: boundsRect(info[kCGWindowBounds as String]),
          cgTitle: info[kCGWindowName as String] as? String ?? "",
          layer: info[kCGWindowLayer as String] as? Int ?? 0))
    }
    return out
  }
}
