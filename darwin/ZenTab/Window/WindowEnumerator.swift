import AppKit

/// Builds the actionable window list off the main thread and returns `Sendable`
/// `WindowInfo` values for one summon.
///
/// The window set comes from `WindowRegistry`'s instant snapshot (captured on the main
/// actor by the caller), which the observers + seed keep current **off** the summon
/// path. So there is no per-summon AX hammer: enumeration is a registry read, ordered
/// and bounds-enriched by a single CoreGraphics pass. CoreGraphics never *adds* a
/// window (a CG-only entry with no AX window behind it has nothing we could focus, so
/// it never appears); it only supplies current-Space z-order, visible-Space membership
/// (the on-screen set), and live bounds. Each of the three modes is the same snapshot
/// run through its fixed filter profile (`collect`).
enum WindowEnumerator {
  /// `monitorFrame` (CoreGraphics coords) restricts the scoped modes to one monitor;
  /// pass nil to span all monitors (the `everything` mode always spans all).
  ///
  /// `registryWindows` / `windowlessApps` are the instant snapshot from
  /// `WindowRegistry`, captured on the main actor by the caller. All three modes are
  /// built from it (no per-summon AX hammer); CoreGraphics only enriches bounds and
  /// provides current-Space z-order. `windowlessApps` are app-only entries shown last
  /// in the current-app / everything modes.
  static func enumerate(
    mode: SwitchMode, frontmostPID: pid_t?, selfPID: pid_t, monitorFrame: CGRect?,
    registryWindows: [WindowInfo], windowlessApps: [WindowInfo] = []
  ) async -> [WindowInfo] {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(
          returning: collect(
            mode: mode, frontmostPID: frontmostPID, monitorFrame: monitorFrame,
            registryWindows: registryWindows, windowlessApps: windowlessApps))
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

  // MARK: - Collection

  /// All three modes are built from `WindowRegistry`'s instant snapshot. The only
  /// difference is the **fixed filter profile** per mode (the authoritative behavior
  /// table from the user's alt-tab config), applied here. CoreGraphics is read once,
  /// off the AX path, purely to enrich current bounds and to provide the current-Space
  /// z-order + visible-Space membership (the on-screen set). No window is ever added
  /// by CoreGraphics: a CG-only entry with no AX window behind it (Finder's desktop, a
  /// helper, a phantom) has nothing we could focus, so it never appears.
  ///
  /// | Mode | Apps | Spaces | Screens | Min | Hidden | Fullscreen | Windowless |
  /// |--|--|--|--|--|--|--|--|
  /// | otherApps | all | visible | switcher's | hide | hide | hide | hide |
  /// | currentApp | active | all | all | show | show | show | at end |
  /// | everything | all | all | all | show | show | show | at end |
  private static func collect(
    mode: SwitchMode, frontmostPID: pid_t?, monitorFrame: CGRect?,
    registryWindows: [WindowInfo], windowlessApps: [WindowInfo]
  ) -> [WindowInfo] {
    let pids = Set(registryWindows.map(\.pid))
    let include: (pid_t) -> Bool = { pids.contains($0) }
    let cg = Dictionary(
      windowEntries(onScreenOnly: false, include: include).map { ($0.windowID, $0) },
      uniquingKeysWith: { first, _ in first })
    // Current-Space, visible, on-screen windows in true front-to-back z-order. Doubles
    // as the "visible Spaces" membership test: a window here is on a visible Space.
    let zOrder = onScreenZOrder(include: include)
    let onScreenWids = Set(zOrder.keys)

    let enriched = registryWindows.map { enrich($0, cg[$0.windowID]) }

    let filtered = enriched.filter { window in
      switch mode {
      case .everything:
        // Everything, everywhere, every state.
        return WindowInfo.isSwitchable(window, includeMinimized: true)
      case .currentApp:
        // The active app, but all its windows anywhere (all Spaces/screens, including
        // minimized / hidden / fullscreen).
        return window.pid == frontmostPID
          && WindowInfo.isSwitchable(window, includeMinimized: true)
      case .otherApps:
        // What's live right here: every app, but only real on-screen windows on a
        // visible Space and the switcher's monitor (no minimized / hidden / fullscreen
        // — those are all absent from the on-screen set, except fullscreen which we
        // drop explicitly).
        return onScreenWids.contains(window.windowID)
          && !window.isFullscreen
          && window.isOnMonitor(monitorFrame)
          && WindowInfo.isSwitchable(window)
      }
    }

    let ordered = orderStably(filtered, zOrder: zOrder)

    // Windowless apps last (Dock-click-style reopen on select). Hidden in otherApps.
    let tail: [WindowInfo]
    switch mode {
    case .everything:
      tail = windowlessApps.sorted { $0.appName.lowercased() < $1.appName.lowercased() }
    case .currentApp:
      tail = windowlessApps.filter { $0.pid == frontmostPID }
    case .otherApps:
      tail = []
    }
    return ordered + tail
  }

  /// Enrich a registry window with CoreGraphics' current bounds / title where it has
  /// them (CG geometry is authoritative for the live frame; the registry's cached
  /// frame is the fallback for windows CG doesn't report).
  private static func enrich(_ window: WindowInfo, _ cg: Entry?) -> WindowInfo {
    let bounds = cg.map { $0.bounds == .zero ? window.frame : $0.bounds } ?? window.frame
    let title = window.title.isEmpty ? (cg?.cgTitle ?? window.appName) : window.title
    return WindowInfo(
      pid: window.pid, windowID: window.windowID, title: title, appName: window.appName,
      frame: bounds, isMinimized: window.isMinimized, isFullscreen: window.isFullscreen,
      subrole: window.subrole, bundleURL: window.bundleURL)
  }

  /// On-screen (current-Space) windows first in z-order, then the rest grouped stably
  /// by app. Stable so the list never reshuffles by recency (the VISION rule).
  private static func orderStably(
    _ windows: [WindowInfo], zOrder: [CGWindowID: Int]
  ) -> [WindowInfo] {
    let onScreen =
      windows.filter { zOrder[$0.windowID] != nil }
      .sorted { zOrder[$0.windowID]! < zOrder[$1.windowID]! }
    let elsewhere =
      windows.filter { zOrder[$0.windowID] == nil }
      .sorted { ($0.appName.lowercased(), $0.windowID) < ($1.appName.lowercased(), $1.windowID) }
    return onScreen + elsewhere
  }

  // MARK: - CoreGraphics sources

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

  private static func boundsRect(_ value: Any?) -> CGRect {
    guard let dictionary = value as? NSDictionary,
      let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    else { return .zero }
    return rect
  }
}
