import AppKit
import ApplicationServices
import notify

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
  private var secureInputHotkeys: SecureInputHotkeys?
  private var watchdog: CaptureWatchdog?
  private var permissionTimer: Timer?
  /// Wake / unlock / display-change observers that rebuild the tap (see `installRecoveryTriggers`).
  private var recoveryObservers: [NSObjectProtocol] = []
  private var dumpSignalSource: DispatchSourceSignal?
  private var previewSignalSource: DispatchSourceSignal?
  /// Dev-only red/green "hands off" light under the notch, driven from a shell test loop.
  private var statusPill: StatusPill?

  private init() {}

  func bootstrap() {
    // Cap how long a hung app can block our Accessibility reads (alt-tab does the same).
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
    // Restore the native switchers if we ever die without a clean quit (the disabled
    // state persists across process exit), so Cmd+Tab is never permanently lost.
    NativeHotkeyRestore.installCrashGuards()
    // ZenTab is useless unless it's already resident when you reach for the switcher, so
    // it launches at login by default — no toggle (VISION.md). Dev builds opt out.
    LoginItem.ensureRegistered(profile: profile)
    config = ConfigStore.load(profile: profile)
    refreshPermissions()
    // Start the window registry's observers off the summon path. AX permission is
    // required to receive events; if it isn't granted yet the permission timer
    // re-attempts via startSwitcherIfPossible (start() is idempotent).
    if Permissions.isAccessibilityTrusted { WindowTracker.shared.start() }
    startSwitcherIfPossible()
    installDumpSignal()
    installRecoveryTriggers()
    // Dev-only "hands off" light under the notch while an automated test loop drives the app.
    if profile == .development {
      let pill = StatusPill()
      pill.startWatching()
      statusPill = pill
    }

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
    secureInputHotkeys?.stop()
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

  /// Show the redesigned overlay populated from running apps, without the hotkey — a dev
  /// affordance for iterating on the look. `board` true → two-zone board; false → flat grid.
  func previewOverlay(board: Bool) { overlay?.preview(board: board) }
  func togglePreviewOverlay(board: Bool) { overlay?.togglePreview(board: board) }

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
    let registrySummary =
      "# registry: \(WindowRegistry.shared.windowCount) windows across "
      + "\(WindowRegistry.shared.appCount) tracked apps\n"
    // Capture the registry snapshot on the main actor and run the REAL enumeration for
    // each mode, so the dump shows exactly the list each shortcut would produce (the
    // probe below is the independent brute-force cross-check, not the shipped path).
    let snapshot = WindowRegistry.shared.windowSnapshot()
    let windowlessApps = WindowRegistry.shared.windowlessAppEntries()
    let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
    diagnostics = "Dumping switchability…"
    Task { [weak self] in
      var modeDump = "# --- actual mode output (registry-backed enumeration) ---\n"
      for mode in [SwitchMode.everything, .currentApp, .otherApps] {
        let list = await WindowEnumerator.enumerate(
          mode: mode, frontmostPID: frontmost, selfPID: selfPID, monitorFrame: nil,
          registryWindows: snapshot, windowlessApps: windowlessApps)
        modeDump += "## \(mode) → \(list.count) entries\n"
        for window in list {
          modeDump +=
            "   \(window.isWindowlessApp ? "[app] " : "")\(window.appName) — \(window.title)\n"
        }
      }
      let probes = await SwitchabilityProbe.collect(
        selfPID: selfPID, mainScreenUUID: mainScreenUUID)
      let path = (NSHomeDirectory() as NSString).appendingPathComponent("zentab-switchability.txt")
      try? (registrySummary + modeDump + "\n" + Self.formatProbes(probes)).write(
        toFile: path, atomically: true, encoding: .utf8)
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
      let probes = await SwitchabilityProbe.collect(
        selfPID: selfPID, mainScreenUUID: mainScreenUUID)
      let summary = await WindowThumbnail.hwCaptureSummary(for: probes.map(\.windowID))
      await MainActor.run { self?.diagnostics = summary }
    }
  }

  private static func formatProbes(_ probes: [SwitchabilityProbe.Sample]) -> String {
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

    // SIGUSR2 toggles the redesigned overlay preview, so the look can be screenshotted
    // from a shell (`killall -USR2 ZenTab`) without holding a hotkey. Dev affordance.
    signal(SIGUSR2, SIG_IGN)
    let previewSource = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
    previewSource.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.togglePreviewOverlay(board: true) }
    }
    previewSource.resume()
    previewSignalSource = previewSource
  }

  /// Rebuild the event tap at the moments macOS is known to drop or wedge taps without
  /// a `tapDisabledBy*` event: wake from sleep, screens waking, the session becoming
  /// active again (unlock, fast user switching) and display reconfiguration. The 2 s
  /// watchdog would catch a tap that reads as disabled; these catch the ones that don't.
  ///
  /// Also listens for test notifications (`notifyutil -p org.nepjua.ZenTab.test.<name>`),
  /// so each failure can be forced from a shell and the self-heal watched in the log.
  private func installRecoveryTriggers() {
    let workspace = NSWorkspace.shared.notificationCenter
    let triggers: [(NotificationCenter, Notification.Name, String)] = [
      (workspace, NSWorkspace.didWakeNotification, "wake"),
      (workspace, NSWorkspace.screensDidWakeNotification, "screens woke"),
      (workspace, NSWorkspace.sessionDidBecomeActiveNotification, "session active"),
      (.default, NSApplication.didChangeScreenParametersNotification, "display change"),
    ]
    for (center, name, reason) in triggers {
      recoveryObservers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.watchdog?.recover(reason: reason) }
        })
    }

    let hooks: [(String, @MainActor (AppModel) -> Void)] = [
      ("disable-tap", { $0.hotkeyTap?.simulateSystemDisable() }),
      ("kill-tap", { $0.hotkeyTap?.simulateTapDeath() }),
      ("secure-input-on", { _ in zt_EnableSecureEventInput() }),
      ("secure-input-off", { _ in zt_DisableSecureEventInput() }),
    ]
    for (name, action) in hooks {
      var token: Int32 = 0
      notify_register_dispatch("org.nepjua.ZenTab.test.\(name)", &token, .main) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          Log.input.notice("test hook: \(name, privacy: .public)")
          action(self)
        }
      }
    }
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
        cancel: { [weak overlay] in overlay?.cancel() },
        closeSelected: { [weak overlay] in overlay?.closeSelected() },
        quitSelected: { [weak overlay] in overlay?.quitSelected() },
        summonSelected: { [weak overlay] in overlay?.summonSelected() },
        flingSelected: { [weak overlay] direction in overlay?.flingSelected(direction) }))

    guard tap.start() else { return }  // tapCreate fails only without Accessibility

    let watchdog = CaptureWatchdog(
      tap: tap,
      bindings: [config.currentApp, config.otherApps, config.everything])
    watchdog.onHealthChange = { [weak self] health in self?.captureHealth = health }

    self.overlay = overlay
    self.hotkeyTap = tap
    // Same chords, in trigger order, as Carbon hot keys: they still fire under Secure
    // Event Input, where the tap never sees the key-down.
    let fallback = SecureInputHotkeys(bindings: triggers.map(\.binding)) { index, backward in
      tap.fallbackTriggerPressed(index: index, backward: backward)
    }
    fallback.start()
    self.secureInputHotkeys = fallback
    self.watchdog = watchdog
    switcherRunning = true
    // Claim Cmd+Tab immediately (only now that the tap is live), so there's no window
    // where the native switcher still fires before the first timer tick.
    watchdog.tick()
  }
}
