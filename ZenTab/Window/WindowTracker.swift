import AppKit
import ApplicationServices

/// A non-`Sendable` `AXObserver` ferried onto the seed queue. Same justification as
/// `AXElementBox`: the observer is a thread-safe CFType and we only register
/// notifications on it; all registry mutation stays on the main actor.
struct AXObserverBox: @unchecked Sendable {
  let observer: AXObserver
}

/// Pack `(pid, wid)` into an AX subscription refcon, so the C callback gets the
/// identity for free (no AX round-trip per event). App-level subscriptions pass
/// `wid == 0` (their subject window varies per event and is read from `element`);
/// per-window subscriptions pass the real wid (reliable even after destruction).
private func packRefcon(_ pid: pid_t, _ wid: CGWindowID = 0) -> UnsafeMutableRawPointer? {
  let packed = (UInt(UInt32(bitPattern: pid)) << 32) | UInt(wid)
  return UnsafeMutableRawPointer(bitPattern: packed)
}

private func unpackRefcon(_ refcon: UnsafeMutableRawPointer?) -> (pid: pid_t, wid: CGWindowID) {
  let packed = UInt(bitPattern: refcon)
  return (
    pid_t(bitPattern: UInt32(truncatingIfNeeded: packed >> 32)),
    CGWindowID(truncatingIfNeeded: packed)
  )
}

/// The single C callback for every AX observer. It carries no captured state (it is a
/// C function pointer), so it routes into `WindowTracker.shared`. Observer run-loop
/// sources are attached to the **main** run loop, so this fires on the main thread;
/// `assumeIsolated` is therefore valid (no hop, no race).
private let axObserverCallback: AXObserverCallback = { _, element, notification, refcon in
  let type = notification as String
  let (pid, wid) = unpackRefcon(refcon)
  // Box the non-Sendable element so it can cross into the @MainActor closure. The
  // source is on the main run loop, so this already runs on the main thread (no hop).
  let box = AXElementBox(element: element)
  MainActor.assumeIsolated {
    WindowTracker.shared.handleAXEvent(type: type, element: box, pid: pid, wid: wid)
  }
}

/// Keeps `WindowRegistry` current **off** the summon path. Per running regular app it
/// creates an `AXObserver` (run-loop source on the main loop) subscribed to the app's
/// window lifecycle, seeds the app's existing windows once (attribute list + the
/// brute-force remote-token scan that reaches other Spaces), and tears everything down
/// when the app quits. Event-driven: no polling-all-apps timer (only the one-time
/// per-app seed and the per-event ingest run AX off-main).
@MainActor
final class WindowTracker {
  static let shared = WindowTracker()
  private init() {}

  private let registry = WindowRegistry.shared
  /// Heavy AX work (brute-force seed, per-event attribute reads) runs here, serialized
  /// and at low priority so it never spikes CPU or blocks the main thread / summon.
  private let seedQueue = DispatchQueue(
    label: "org.nepjua.ZenTab.windowTracker.seed", qos: .utility)
  /// Window ids we have already given a per-window subscription, so repeated focus
  /// events don't re-subscribe the same window.
  private var subscribedWindows: Set<CGWindowID> = []
  /// Last activation-refresh time per app (throttle), in mach-uptime nanoseconds.
  private var lastActivationRefresh: [pid_t: UInt64] = [:]
  private var started = false

  /// The private AX attribute for native (green-button) fullscreen. There is no
  /// public constant; the WindowServer/AX string is "AXFullScreen".
  private nonisolated static let fullscreenAttribute = "AXFullScreen"

  private nonisolated static let appNotifications = [
    kAXWindowCreatedNotification,
    kAXFocusedWindowChangedNotification,
    kAXMainWindowChangedNotification,
    kAXApplicationActivatedNotification,
    kAXApplicationHiddenNotification,
    kAXApplicationShownNotification,
  ]
  private nonisolated static let windowNotifications = [
    kAXUIElementDestroyedNotification,
    kAXWindowMiniaturizedNotification,
    kAXWindowDeminiaturizedNotification,
  ]

  // MARK: - Lifecycle

  func start() {
    guard !started else { return }
    started = true
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(
      self, selector: #selector(appLaunched(_:)),
      name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    center.addObserver(
      self, selector: #selector(appTerminated(_:)),
      name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
      addApp(app)
    }
  }

  @objc private func appLaunched(_ note: Notification) {
    guard
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
      app.activationPolicy == .regular
    else { return }
    addApp(app)
  }

  @objc private func appTerminated(_ note: Notification) {
    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    else { return }
    removeApp(pid: app.processIdentifier)
  }

  private func addApp(_ runningApp: NSRunningApplication) {
    let pid = runningApp.processIdentifier
    guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier, !registry.isTracking(pid: pid)
    else { return }

    let appElement = AXUIElementCreateApplication(pid)
    var observer: AXObserver?
    guard AXObserverCreate(pid, axObserverCallback, &observer) == .success, let observer
    else { return }

    // Attach to the main run loop so the C callback fires on the main thread.
    CFRunLoopAddSource(
      CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)

    let record = AppObservation(pid: pid, runningApplication: runningApp, appElement: appElement)
    record.observer = observer
    registry.setApp(record)

    // Subscribe + seed off-main: an unresponsive app must never stall launch.
    let appBox = AXElementBox(element: appElement)
    let observerBox = AXObserverBox(observer: observer)
    seedQueue.async { [weak self] in
      self?.subscribeAndSeed(pid: pid, app: appBox, observer: observerBox)
    }
  }

  private func removeApp(pid: pid_t) {
    if let observer = registry.app(for: pid)?.observer {
      CFRunLoopRemoveSource(
        CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    lastActivationRefresh[pid] = nil
    registry.removeApp(pid: pid)
    // Drop per-window subscription bookkeeping for windows that just went away.
    for wid in subscribedWindows where !registry.hasWindow(wid: wid) { subscribedWindows.remove(wid) }
  }

  // MARK: - AX event routing (main thread)

  func handleAXEvent(type: String, element: AXElementBox, pid: pid_t, wid: CGWindowID) {
    switch type {
    case kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
      kAXMainWindowChangedNotification:
      ingestWindow(element, pid: pid)
    case kAXUIElementDestroyedNotification:
      if wid != 0 {
        registry.removeWindow(wid: wid)
        subscribedWindows.remove(wid)
      }
    case kAXWindowMiniaturizedNotification:
      if wid != 0 { registry.setMinimized(true, wid: wid) }
    case kAXWindowDeminiaturizedNotification:
      if wid != 0 { registry.setMinimized(false, wid: wid) }
    case kAXApplicationActivatedNotification:
      // Focus events only carry the one focused window; refresh the whole app's
      // current-Space window list when you switch to it, so a multi-window app shows
      // all its windows. Attribute-only (no brute-force) and throttled, so it stays
      // cheap and event-driven (no polling).
      refreshAppWindowsThrottled(pid: pid)
    default:
      // Hidden/Shown: app `isHidden` is read live at snapshot time, nothing to cache.
      break
    }
  }

  /// Re-read an app's current-Space windows (attribute list only) at most once per
  /// second per app, off-main, and upsert them.
  private func refreshAppWindowsThrottled(pid: pid_t) {
    let now = DispatchTime.now().uptimeNanoseconds
    if let last = lastActivationRefresh[pid], now - last < 1_000_000_000 { return }
    lastActivationRefresh[pid] = now
    guard let appElement = registry.app(for: pid)?.appElement else { return }
    let appBox = AXElementBox(element: appElement)
    seedQueue.async { [weak self] in
      self?.seedWindows(pid: pid, app: appBox, bruteForce: false)
    }
  }

  /// Read a single window's attributes off-main, then upsert it (and give it a
  /// per-window subscription the first time we see it).
  private func ingestWindow(_ elementBox: AXElementBox, pid: pid_t) {
    seedQueue.async { [weak self] in
      guard let detail = Self.readWindow(elementBox.element, pid: pid) else { return }
      DispatchQueue.main.async {
        self?.applyWindow(detail)
      }
    }
  }

  // MARK: - Seeding (seed queue)

  /// Subscribe the app element to the lifecycle notifications, then seed its existing
  /// windows (attribute list for the current Space + brute-force for other Spaces).
  private nonisolated func subscribeAndSeed(pid: pid_t, app: AXElementBox, observer: AXObserverBox) {
    for notification in Self.appNotifications {
      AXObserverAddNotification(
        observer.observer, app.element, notification as CFString, packRefcon(pid))
    }
    seedWindows(pid: pid, app: app, bruteForce: true)
  }

  /// Read an app's windows off-main (`bruteForce` adds the other-Space remote-token
  /// scan; off for the cheap activation refresh) and upsert them on main.
  private nonisolated func seedWindows(pid: pid_t, app: AXElementBox, bruteForce: Bool) {
    var seen = Set<CGWindowID>()
    var details: [WindowDetail] = []
    for window in Self.allWindows(pid: pid, appElement: app.element, bruteForce: bruteForce) {
      guard let detail = Self.readWindow(window, pid: pid), !seen.contains(detail.wid) else {
        continue
      }
      seen.insert(detail.wid)
      details.append(detail)
    }
    DispatchQueue.main.async { [weak self] in
      for detail in details { self?.applyWindow(detail) }
    }
  }

  /// Upsert a window into the registry and, the first time, give it a per-window
  /// subscription (destroy / miniaturize / deminiaturize). Runs on main.
  private func applyWindow(_ detail: WindowDetail) {
    guard registry.isTracking(pid: detail.pid) else { return }  // app quit mid-flight
    registry.upsert(
      RegistryWindow(
        element: detail.box.element, pid: detail.pid, subrole: detail.subrole,
        title: detail.title, isMinimized: detail.isMinimized,
        isFullscreen: detail.isFullscreen, frame: detail.frame),
      wid: detail.wid)
    guard !subscribedWindows.contains(detail.wid),
      let observer = registry.app(for: detail.pid)?.observer
    else { return }
    subscribedWindows.insert(detail.wid)
    for notification in Self.windowNotifications {
      AXObserverAddNotification(
        observer, detail.box.element, notification as CFString,
        packRefcon(detail.pid, detail.wid))
    }
  }

  // MARK: - Off-main AX reads

  /// A window snapshot taken off-main, carrying its (non-`Sendable`) AX element across
  /// to the main actor for storage.
  private struct WindowDetail: @unchecked Sendable {
    let box: AXElementBox
    let wid: CGWindowID
    let pid: pid_t
    let subrole: String
    let title: String
    let isMinimized: Bool
    let isFullscreen: Bool
    let frame: CGRect
  }

  /// Read a window element's id + the attributes the switcher needs. Returns nil if it
  /// has no window id or is an explicit non-window subrole (palette / system dialog).
  private nonisolated static func readWindow(_ element: AXUIElement, pid: pid_t) -> WindowDetail? {
    var wid: CGWindowID = 0
    guard _AXUIElementGetWindow(element, &wid) == .success, wid != 0 else { return nil }
    let subrole = copyAttribute(element, kAXSubroleAttribute) as? String ?? ""
    guard !WindowInfo.nonWindowSubroles.contains(subrole) else { return nil }
    let origin = axPoint(element, kAXPositionAttribute) ?? .zero
    let size = axSize(element, kAXSizeAttribute) ?? .zero
    return WindowDetail(
      box: AXElementBox(element: element),
      wid: wid, pid: pid, subrole: subrole,
      title: copyAttribute(element, kAXTitleAttribute) as? String ?? "",
      isMinimized: (copyAttribute(element, kAXMinimizedAttribute) as? Bool) ?? false,
      isFullscreen: (copyAttribute(element, fullscreenAttribute) as? Bool) ?? false,
      frame: CGRect(origin: origin, size: size))
  }

  /// Every window of `pid`: the AX attribute list (current Space), optionally unioned
  /// with the brute-force remote-token scan (other Spaces). Mirrors alt-tab's
  /// `allWindows`. The seed passes `bruteForce: true` to reach other Spaces once; the
  /// activation refresh passes `false` (current Space is enough and cheaper).
  private nonisolated static func allWindows(
    pid: pid_t, appElement: AXUIElement, bruteForce: Bool
  ) -> [AXUIElement] {
    var windows = (copyAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    if bruteForce { windows += bruteForceWindows(pid: pid) }
    return windows
  }

  /// Other-Space windows of `pid`, reconstructed from their 20-byte remote tokens
  /// (`pid` · 0 · 0x636f636f · `AXUIElementID`). Bounded to 1000 ids / 100ms per app
  /// and filtered to real window subroles. This is the one-time seed for windows that
  /// existed before we began observing; new windows arrive via `kAXWindowCreated`.
  private nonisolated static func bruteForceWindows(pid: pid_t) -> [AXUIElement] {
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

  private nonisolated static func copyAttribute(
    _ element: AXUIElement, _ attribute: String
  ) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
      return nil
    }
    return value
  }

  private nonisolated static func axValue(
    _ element: AXUIElement, _ attribute: String
  ) -> AXValue? {
    guard let value = copyAttribute(element, attribute), CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    // swiftlint:disable:next force_cast
    return (value as! AXValue)
  }

  private nonisolated static func axPoint(
    _ element: AXUIElement, _ attribute: String
  ) -> CGPoint? {
    guard let value = axValue(element, attribute) else { return nil }
    var point = CGPoint.zero
    return AXValueGetValue(value, .cgPoint, &point) ? point : nil
  }

  private nonisolated static func axSize(
    _ element: AXUIElement, _ attribute: String
  ) -> CGSize? {
    guard let value = axValue(element, attribute) else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(value, .cgSize, &size) ? size : nil
  }
}
