import AppKit
import ApplicationServices

/// Read-only switchability diagnostic, kept apart from the production enumerator so it
/// can stay heavy without touching the hot path. The menu's "Dump switchability" /
/// SIGUSR1 action writes one `Sample` per everything-mode candidate window with every
/// signal we have, so we can see exactly why a window is or isn't switchable. It runs
/// its OWN brute-force AX scan (an independent cross-check of the registry-backed
/// enumeration), which is why it does not share the enumerator's code.
enum SwitchabilityProbe {
  /// One everything-mode candidate window with every signal we have, captured BEFORE
  /// any switchability filtering. The instrument for evolving `WindowInfo.isSwitchable`
  /// as we learn new focus tricks (the principle: only show windows we can switch to).
  struct Sample: Sendable {
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

  static func collect(selfPID: pid_t, mainScreenUUID: String?) async -> [Sample] {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(returning: gather(selfPID: selfPID, mainScreenUUID: mainScreenUUID))
      }
    }
  }

  private static let queue = DispatchQueue(
    label: "org.nepjua.ZenTab.probe", qos: .userInitiated)

  // MARK: - Gather

  private static func gather(selfPID: pid_t, mainScreenUUID: String?) -> [Sample] {
    let candidates = candidatePIDs(selfPID: selfPID)
    let include: (pid_t) -> Bool = { candidates.contains($0) }

    let cgAll = rawCGWindows(onScreenOnly: false, include: include)
    let onScreenIDs = Set(rawCGWindows(onScreenOnly: true, include: include).map(\.windowID))
    let ax = axDetails(for: candidates)
    let cgByID = Dictionary(cgAll.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })

    let currentSpace = mainScreenUUID.map {
      CGSManagedDisplayGetCurrentSpace(cgsConnection, $0 as CFString)
    }

    var ids = Set(cgAll.map(\.windowID))
    ids.formUnion(ax.keys)

    var samples: [Sample] = []
    for windowID in ids {
      let cg = cgByID[windowID]
      let detail = ax[windowID]
      let pid = detail?.pid ?? cg?.pid ?? 0
      let appName = (detail.map { $0.appName.isEmpty ? nil : $0.appName } ?? nil) ?? cg?.ownerName ?? ""
      let axTitle = detail?.title ?? ""
      let title = axTitle.isEmpty ? (cg?.cgTitle ?? "") : axTitle
      let frame = detail?.frame ?? cg?.bounds ?? .zero

      // Replicate the merged WindowInfo the production path would build, plus the
      // layer-0 gate, to record whether the window is shown today.
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

      samples.append(
        Sample(
          appName: appName, title: title, pid: pid, windowID: windowID,
          cgLayer: cg?.layer, onScreen: onScreenIDs.contains(windowID),
          onCurrentSpace: onCurrentSpace, hasAXWindow: detail != nil,
          role: detail?.role ?? "", subrole: detail?.subrole ?? "",
          minimized: detail?.minimized ?? false,
          width: frame.width, height: frame.height, passesCurrentFilter: passes))
    }
    return samples.sorted { ($0.appName.lowercased(), $0.title) < ($1.appName.lowercased(), $1.title) }
  }

  // MARK: - CoreGraphics

  /// Raw CG window read: ALL layers (no `layer == 0` gate), so we can see chrome /
  /// helper levels too.
  private struct RawCG {
    let windowID: CGWindowID
    let pid: pid_t
    let ownerName: String
    let bounds: CGRect
    let cgTitle: String
    let layer: Int
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

  private static func boundsRect(_ value: Any?) -> CGRect {
    guard let dictionary = value as? NSDictionary,
      let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    else { return .zero }
    return rect
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

  // MARK: - Accessibility (the probe's own brute-force, independent of the registry)

  private struct AXDetail {
    let pid: pid_t
    let appName: String
    let role: String
    let subrole: String
    let minimized: Bool
    let title: String
    let frame: CGRect
  }

  /// AX detail per window id, gathered once per app: `kAXWindowsAttribute` (current
  /// Space) unioned with the brute-force remote-token scan (other Spaces).
  private static func axDetails(for pids: Set<pid_t>) -> [CGWindowID: AXDetail] {
    var details: [CGWindowID: AXDetail] = [:]
    for pid in pids {
      let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
      let axApp = AXUIElementCreateApplication(pid)
      // Attribute windows come first so their (accurate) detail wins on any overlap.
      var axWindows = (copyAttribute(axApp, kAXWindowsAttribute) as? [AXUIElement]) ?? []
      axWindows += bruteForceAXWindows(pid: pid)
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

  /// Other-Space windows of `pid`, reconstructed from their 20-byte remote tokens
  /// (pid · 0 · 0x636f636f · `AXUIElementID`). Bounded to 1000 ids / 100ms per app.
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
}
