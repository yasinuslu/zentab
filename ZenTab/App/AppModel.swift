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
  /// Whether ZenTab is currently, reliably capturing its trigger shortcut. Drives
  /// the menu bar icon. ZenTab never falls back to another key; it reports the truth.
  @Published private(set) var captureHealth: CaptureHealth = .noAccessibility
  /// Result of the menu's "Run diagnostics" private-API smoke test.
  @Published private(set) var diagnostics: String?

  /// Which trigger suite this launch uses (production Cmd+Tab vs. safe dev chords).
  let profile = LaunchProfile.current

  private(set) var config = Config.default
  private var overlay: OverlayController?
  private var hotkeyTap: HotkeyTap?
  private var watchdog: CaptureWatchdog?
  private var permissionTimer: Timer?
  private var dumpSignalSource: DispatchSourceSignal?

  private init() {}

  func bootstrap() {
    // Cap how long a hung app can block our Accessibility reads (alt-tab does the same).
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
    // Restore the native switchers if we ever die without a clean quit (the disabled
    // state persists across process exit), so Cmd+Tab is never permanently lost.
    NativeHotkeyRestore.installCrashGuards()
    config = ConfigStore.load(profile: profile)
    refreshPermissions()
    startSwitcherIfPossible()
    installDumpSignal()

    // Reflect a permission grant (and start the switcher) without a relaunch, and
    // re-assert the Cmd+Tab claim (other apps / macOS can quietly reclaim it).
    permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshPermissions()
        self?.startSwitcherIfPossible()
        self?.watchdog?.tick()
      }
    }
  }

  /// Graceful-quit cleanup: hand the native switchers back to macOS and stop the tap.
  func shutdown() {
    watchdog?.release()
    hotkeyTap?.stop()
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
  /// surfaces here instead of corrupting the stack inside the hot path. Also reports
  /// the live capture picture (resolved profile, the binding, which native hotkeys
  /// we manage and whether they're currently disabled, tap + health) — the fast way
  /// to see *why* Cmd+Tab isn't being captured on a given machine.
  func runDiagnostics() {
    let connection = cgsConnection
    let bindings = [config.currentApp, config.otherApps, config.everything]
    let managed = NativeHotkeyConflict.conflicting(with: bindings)
    let hotkeyStates =
      managed.sorted { $0.rawValue < $1.rawValue }
      .map { "\($0)=\(CGSIsSymbolicHotKeyEnabled($0.rawValue) ? "ON(bad)" : "off(ours)")" }
      .joined(separator: " ")
    let tapState = hotkeyTap?.isEnabled == true ? "enabled" : "disabled/none"
    diagnostics = """
      profile: \(profile.label) · CGS \(connection)
      other_apps: keyCode \(config.otherApps.keyCode) \
      \(config.otherApps.modifiers.contains(.command) ? "⌘" : "")\
      \(config.otherApps.modifiers.contains(.control) ? "⌃" : "")\
      \(config.otherApps.modifiers.contains(.option) ? "⌥" : "") \
      (tab=48, grave=50)
      native switchers: [\(managed.isEmpty ? "none managed — binding isn't Cmd-based" : hotkeyStates)]
      tap: \(tapState) · health: \(captureHealth.summary)
      """
  }

  /// Dump every everything-mode *candidate* window with all its switchability
  /// signals to `~/zentab-switchability.txt`. Read-only: it changes no behavior,
  /// it just shows us why a window is or isn't switchable, so the filter can be
  /// driven by ground truth instead of guesses.
  func dumpSwitchability() {
    let selfPID = ProcessInfo.processInfo.processIdentifier
    let mainScreenUUID = NSScreen.main?.spaceUUID()
    diagnostics = "Dumping switchability…"
    Task { [weak self] in
      let probes = await WindowEnumerator.probeEverything(
        selfPID: selfPID, mainScreenUUID: mainScreenUUID)
      let path = (NSHomeDirectory() as NSString).appendingPathComponent("zentab-switchability.txt")
      try? Self.formatProbes(probes).write(toFile: path, atomically: true, encoding: .utf8)
      await MainActor.run {
        let shown = probes.filter(\.passesCurrentFilter).count
        self?.diagnostics = "Wrote \(probes.count) windows (\(shown) shown) → \(path)"
      }
    }
  }

  /// Smoke-test the private `CGSHWCaptureWindowList` binding before it goes in the
  /// hot path: capture every everything-mode window via the hardware path and report
  /// how many succeeded (this is the cross-Space / minimized capture SCK can't do).
  func runCaptureDiagnostics() {
    let selfPID = ProcessInfo.processInfo.processIdentifier
    let mainScreenUUID = NSScreen.main?.spaceUUID()
    diagnostics = "Testing HW capture…"
    Task { [weak self] in
      let probes = await WindowEnumerator.probeEverything(
        selfPID: selfPID, mainScreenUUID: mainScreenUUID)
      let summary = await WindowThumbnail.hwCaptureSummary(for: probes.map(\.windowID))
      await MainActor.run { self?.diagnostics = summary }
    }
  }

  private static func formatProbes(_ probes: [WindowEnumerator.SwitchabilityProbe]) -> String {
    var lines = [
      "# ZenTab switchability dump — everything-mode candidates, BEFORE filtering",
      "# verdict | onScreen onSpace hasAX | Layer role/subrole min | WxH | app — title",
      "",
    ]
    for probe in probes {
      let flags =
        "\(probe.onScreen ? "scr" : "---") "
        + "\(probe.onCurrentSpace ? "spc" : "---") "
        + "\(probe.hasAXWindow ? "AX" : "--")"
      let layer = probe.cgLayer.map { "L\($0)" } ?? "L·"
      let role = probe.role.isEmpty ? "-" : probe.role
      let subrole = probe.subrole.isEmpty ? "-" : probe.subrole
      lines.append(
        "\(probe.passesCurrentFilter ? "SHOWN" : "hide ") | \(flags) | "
          + "\(layer) \(role)/\(subrole) \(probe.minimized ? "min" : "   ") | "
          + "\(Int(probe.width))x\(Int(probe.height)) | \(probe.appName) — \(probe.title)")
    }
    return lines.joined(separator: "\n") + "\n"
  }

  /// Trigger a switchability dump on `SIGUSR1` (`kill -USR1 <pid>` / `killall -USR1
  /// ZenTab`), so the dump can be driven from the shell without a menu click — used
  /// to investigate the window list headlessly.
  private func installDumpSignal() {
    signal(SIGUSR1, SIG_IGN)  // let the dispatch source own it instead of the default (terminate)
    let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.dumpSwitchability() }
    }
    source.resume()
    dumpSignalSource = source
  }

  private func startSwitcherIfPossible() {
    guard !switcherRunning, Permissions.isAccessibilityTrusted else { return }

    let overlay = OverlayController(config: config)
    let triggers = [
      HotkeyTap.Trigger(mode: .currentApp, binding: config.currentApp),
      HotkeyTap.Trigger(mode: .otherApps, binding: config.otherApps),
      HotkeyTap.Trigger(mode: .everything, binding: config.everything),
    ]
    let tap = HotkeyTap(
      triggers: triggers,
      handlers: HotkeyTap.Handlers(
        summon: { [weak overlay] mode in overlay?.summon(mode: mode) },
        cycle: { [weak overlay] backward in overlay?.cycle(backward: backward) },
        confirm: { [weak overlay] in overlay?.confirm() },
        cancel: { [weak overlay] in overlay?.cancel() }))

    guard tap.start() else { return }  // tapCreate fails only without Accessibility

    let watchdog = CaptureWatchdog(
      tap: tap,
      bindings: [config.currentApp, config.otherApps, config.everything])
    watchdog.onHealthChange = { [weak self] health in self?.captureHealth = health }

    self.overlay = overlay
    self.hotkeyTap = tap
    self.watchdog = watchdog
    switcherRunning = true
    // Claim Cmd+Tab immediately (only now that the tap is live), so there's no window
    // where the native switcher still fires before the first timer tick.
    watchdog.tick()
  }
}
