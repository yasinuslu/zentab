import AppKit
import ApplicationServices

/// App-wide state shared by the lifecycle (`AppDelegate`) and the menu bar
/// (`MenuBarContent`). Owns the long-lived switcher objects and tracks the two TCC
/// permissions. Lives entirely on the main actor.
@MainActor
final class AppModel: ObservableObject {
  static let shared = AppModel()

  @Published private(set) var accessibilityTrusted = false
  @Published private(set) var screenRecordingGranted = false
  @Published private(set) var switcherRunning = false
  /// Result of the menu's "Run diagnostics" private-API smoke test.
  @Published private(set) var diagnostics: String?

  private(set) var config = Config.default
  private var overlay: OverlayController?
  private var hotkeyTap: HotkeyTap?
  private var permissionTimer: Timer?

  private init() {}

  func bootstrap() {
    // Cap how long a hung app can block our Accessibility reads (alt-tab does the same).
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
    config = ConfigStore.load()
    refreshPermissions()
    startSwitcherIfPossible()

    // Reflect a permission grant (and start the switcher) without a relaunch.
    permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshPermissions()
        self?.startSwitcherIfPossible()
      }
    }
  }

  func refreshPermissions() {
    accessibilityTrusted = Permissions.isAccessibilityTrusted
    screenRecordingGranted = Permissions.hasScreenRecording
  }

  func requestAccessibility() {
    Permissions.requestAccessibility()
    Permissions.openAccessibilitySettings()
  }

  func requestScreenRecording() {
    Permissions.requestScreenRecording()
    Permissions.openScreenRecordingSettings()
  }

  /// Smoke-test each private symbol in isolation, so a bad `@_silgen_name` binding
  /// surfaces here instead of corrupting the stack inside the hot path.
  func runDiagnostics() {
    let connection = cgsConnection
    var psn = ProcessSerialNumber()
    let status = zt_GetProcessForPID(ProcessInfo.processInfo.processIdentifier, &psn)
    diagnostics =
      "CGS connection \(connection) · GetProcessForPID \(status) · PSN "
      + "\(psn.highLongOfPSN):\(psn.lowLongOfPSN)"
  }

  private func startSwitcherIfPossible() {
    guard !switcherRunning, Permissions.isAccessibilityTrusted else { return }

    let overlay = OverlayController(config: config)
    let tap = HotkeyTap(
      binding: config.otherApps,
      handlers: HotkeyTap.Handlers(
        summon: { [weak overlay] in overlay?.summon() },
        cycle: { [weak overlay] backward in overlay?.cycle(backward: backward) },
        confirm: { [weak overlay] in overlay?.confirm() },
        cancel: { [weak overlay] in overlay?.cancel() }))

    guard tap.start() else { return }  // tapCreate fails only without Accessibility
    self.overlay = overlay
    self.hotkeyTap = tap
    switcherRunning = true
  }
}
