import AppKit
import ApplicationServices

/// Ferries a non-`Sendable` AX handle across a concurrency boundary. `AXUIElement`
/// is a thread-safe CFType that we only ever read from or send actions to, and all
/// registry mutation stays on the main actor, so this unchecked conformance is sound.
struct AXElementBox: @unchecked Sendable {
  let element: AXUIElement
}

/// A live window record: the cached AX handle plus the metadata the switcher needs.
/// Captured **off** the summon path (by `WindowTracker`'s observers + seed) so that
/// enumeration is an instant in-memory read instead of a per-summon AX hammer.
@MainActor
struct RegistryWindow {
  let element: AXUIElement
  let pid: pid_t
  var subrole: String
  var title: String
  var isMinimized: Bool
  var isFullscreen: Bool
  var frame: CGRect
}

/// One tracked application: its AX element + observer (so we can detach on quit) and
/// the identity used to label windows and to reopen the app when it is windowless.
@MainActor
final class AppObservation {
  let pid: pid_t
  let runningApplication: NSRunningApplication
  let appElement: AXUIElement
  var observer: AXObserver?
  let appName: String
  let bundleURL: URL?
  /// Set once the first subscription succeeds; gates the one-time seed.
  var seeded = false

  init(pid: pid_t, runningApplication: NSRunningApplication, appElement: AXUIElement) {
    self.pid = pid
    self.runningApplication = runningApplication
    self.appElement = appElement
    self.appName = runningApplication.localizedName ?? ""
    self.bundleURL = runningApplication.bundleURL
  }
}

/// The persistent, main-actor window store. `WindowTracker` keeps it current from AX
/// observer callbacks and an initial seed; `WindowEnumerator` and `WindowFocuser`
/// only ever **read** it (an instant snapshot / element lookup), never touch AX on
/// the hot path. This is the whole cross-Space fix: every window's AX element is
/// captured the moment it appears, at any element id, on another Space or not.
@MainActor
final class WindowRegistry {
  static let shared = WindowRegistry()
  private init() {}

  private var windows: [CGWindowID: RegistryWindow] = [:]
  private var apps: [pid_t: AppObservation] = [:]

  // MARK: - App records

  func app(for pid: pid_t) -> AppObservation? { apps[pid] }
  func setApp(_ app: AppObservation) { apps[app.pid] = app }
  func isTracking(pid: pid_t) -> Bool { apps[pid] != nil }

  /// Drop an app and every window it owned (called on terminate).
  func removeApp(pid: pid_t) {
    apps[pid] = nil
    for (wid, window) in windows where window.pid == pid { windows[wid] = nil }
  }

  // MARK: - Window records

  func upsert(_ window: RegistryWindow, wid: CGWindowID) { windows[wid] = window }
  func removeWindow(wid: CGWindowID) { windows[wid] = nil }
  func hasWindow(wid: CGWindowID) -> Bool { windows[wid] != nil }

  func setMinimized(_ minimized: Bool, wid: CGWindowID) {
    windows[wid]?.isMinimized = minimized
  }

  /// The cached AX element for a window id, for `WindowFocuser`'s cross-Space raise
  /// (boxed so it can cross onto the focus queue).
  func axElement(for wid: CGWindowID) -> AXElementBox? {
    windows[wid].map { AXElementBox(element: $0.element) }
  }

  // MARK: - Snapshots (instant reads for enumeration)

  /// Every tracked real window as a `Sendable` value, with its owner app's name.
  /// Order is unspecified; the enumerator imposes z-order / grouping.
  func windowSnapshot() -> [WindowInfo] {
    windows.compactMap { wid, window in
      guard let app = apps[window.pid] else { return nil }
      let title = window.title.isEmpty ? app.appName : window.title
      return WindowInfo(
        pid: window.pid, windowID: wid, title: title, appName: app.appName,
        frame: window.frame, isMinimized: window.isMinimized,
        isFullscreen: window.isFullscreen, subrole: window.subrole,
        isWindowlessApp: false, bundleURL: app.bundleURL)
    }
  }

  /// App-only entries for running regular apps that currently have **no** window in
  /// the registry. Selecting one reopens the app (see `WindowFocuser`). Used by the
  /// current-app / everything modes, ordered last by the enumerator.
  func windowlessAppEntries() -> [WindowInfo] {
    let pidsWithWindows = Set(windows.values.map(\.pid))
    return apps.values.compactMap { app -> WindowInfo? in
      guard !pidsWithWindows.contains(app.pid),
        app.runningApplication.activationPolicy == .regular,
        !app.runningApplication.isTerminated
      else { return nil }
      return WindowInfo(
        pid: app.pid, windowID: 0, title: app.appName, appName: app.appName,
        frame: .zero, isMinimized: false, isFullscreen: false, subrole: "",
        isWindowlessApp: true, bundleURL: app.bundleURL)
    }
  }

  /// Tracked-window count, for diagnostics.
  var windowCount: Int { windows.count }
  var appCount: Int { apps.count }
}
