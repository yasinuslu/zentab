import AppKit

/// The main-actor shell around `OverlaySession`. It owns the AppKit overlay and the
/// real side effects (off-main enumeration, the hold timer, thumbnail capture, focus)
/// but holds **no decision logic**: every input is fed to the pure `OverlaySession`,
/// and whatever `Effect`s it returns are executed here. That keeps the tricky
/// tap-vs-hold / confirm-wins / stale-timer behavior in a unit-tested value type.
@MainActor
final class OverlayController {
  private let config: Config
  private let panel = SwitcherPanel()
  private let grid = TileGridView(frame: .zero)
  private var machine = OverlaySession()
  /// Last-known frame per window, so off-Space / off-monitor windows (which can't be
  /// captured live) still show their latest thumbnail instead of a bare icon.
  private let thumbnailCache = ThumbnailCache()
  /// Keeps the cache warm so a summon paints a recent frame instantly. On-screen
  /// windows only, gently paced, and paused under Low Power to respect the battery.
  private var refreshTimer: Timer?

  // Captured at each summon so the enumeration effect knows what to ask for.
  private var pendingMode: SwitchMode = .otherApps
  private var pendingFrontmostPID: pid_t?
  private var pendingSelfPID: pid_t = 0
  private var pendingMonitorFrame: CGRect?

  init(config: Config) {
    self.config = config
    let container = NSVisualEffectView()
    container.material = .hudWindow
    container.state = .active
    container.blendingMode = .behindWindow
    container.wantsLayer = true
    container.layer?.cornerRadius = 18
    container.layer?.masksToBounds = true
    grid.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(grid)
    NSLayoutConstraint.activate([
      grid.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      grid.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      grid.topAnchor.constraint(equalTo: container.topAnchor),
      grid.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    panel.contentView = container

    grid.onHover = { [weak self] index in self?.send(.hover(index)) }
    grid.onActivate = { [weak self] index in
      self?.send(.hover(index))
      self?.send(.confirm)
    }
    // The on-thumbnail close/quit buttons act on the tile under the mouse: select it
    // first (same as a click), then run the action on that selection.
    grid.onClose = { [weak self] index in
      self?.send(.hover(index))
      self?.send(.closeSelected)
    }
    grid.onQuit = { [weak self] index in
      self?.send(.hover(index))
      self?.send(.quitSelected)
    }

    startBackgroundRefresh()
  }

  // MARK: - Background cache refresh

  /// Periodically snapshot on-screen windows into the thumbnail cache, so the overlay
  /// can paint a recent frame the instant it's summoned (and so a window that later
  /// moves to another Space keeps a fresh last-known frame). Deliberately cheap:
  /// gentle interval, on-screen windows only, skipped while the overlay is up or the
  /// machine is in Low Power Mode.
  private func startBackgroundRefresh() {
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshCache() }
    }
  }

  private func refreshCache() {
    guard !machine.isVisible, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
    Task { [weak self] in
      let captured = await WindowThumbnail.captureOnScreen()
      self?.thumbnailCache.remember(captured.images)
    }
  }

  // MARK: - HotkeyTap handlers

  func summon(mode: SwitchMode) {
    pendingMode = mode
    pendingFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    pendingSelfPID = ProcessInfo.processInfo.processIdentifier
    // Only otherApps is scoped to the switcher's monitor (the behavior table);
    // currentApp and everything span all screens.
    pendingMonitorFrame = mode == .otherApps ? Self.monitorUnderMouse() : nil
    send(.summon)
  }

  func cycle(backward: Bool) { send(.cycle(backward: backward)) }
  func confirm() { send(.confirm) }
  func cancel() { send(.cancel) }
  func closeSelected() { send(.closeSelected) }
  func quitSelected() { send(.quitSelected) }
  func summonSelected() { send(.summonSelected) }
  func flingSelected(_ direction: FlingDirection) { send(.flingSelected(direction)) }

  // MARK: - Reducer plumbing

  private func send(_ event: OverlaySession.Event) {
    for effect in machine.handle(event) { perform(effect) }
  }

  private func perform(_ effect: OverlaySession.Effect) {
    switch effect {
    case .beginEnumeration(let id):
      let mode = pendingMode
      let frontmost = pendingFrontmostPID
      let selfPID = pendingSelfPID
      let monitorFrame = pendingMonitorFrame
      // Instant in-memory read on the main actor (no AX on the summon path).
      let registryWindows = WindowRegistry.shared.windowSnapshot()
      let windowlessApps = WindowRegistry.shared.windowlessAppEntries()
      Task { [weak self] in
        let windows = await WindowEnumerator.enumerate(
          mode: mode, frontmostPID: frontmost, selfPID: selfPID, monitorFrame: monitorFrame,
          registryWindows: registryWindows, windowlessApps: windowlessApps)
        self?.send(.enumerated(windows, currentPID: frontmost, session: id))
      }

    case .scheduleHold(let id):
      DispatchQueue.main.asyncAfter(deadline: .now() + config.holdThreshold) { [weak self] in
        MainActor.assumeIsolated { self?.send(.holdElapsed(session: id)) }
      }

    case .show(let windows, let index):
      showPanel(windows: windows, index: index)

    case .updateSelection(let index):
      grid.updateSelection(index)

    case .relayout(let windows, let index):
      relayoutPanel(windows: windows, index: index)

    case .hide:
      panel.orderOut(nil)

    case .focus(let window):
      if let window { WindowFocuser.focus(window) }

    case .close(let window):
      WindowCloser.close(window)

    case .quit(let pid):
      WindowCloser.quitApp(pid: pid)

    case .summonWindow(let window):
      SpaceMover.summon(window)

    case .flingWindow(let window, let direction):
      SpaceMover.fling(window, direction)
    }
  }

  /// Re-lay the grid after a close/quit dropped windows: resize + re-center the panel,
  /// keeping the live thumbnails already captured for the survivors (no re-capture).
  private func relayoutPanel(windows: [WindowInfo], index: Int) {
    let size = grid.configure(windows: windows, selectedIndex: index, keepThumbnails: true)
    panel.setContentSize(size)
    centerPanel(size: size)
    grid.refreshHoveredTile()  // the survivors shifted under the cursor; re-place badges
  }

  private func showPanel(windows: [WindowInfo], index: Int) {
    let size = grid.configure(windows: windows, selectedIndex: index)
    panel.setContentSize(size)
    centerPanel(size: size)
    panel.makeKeyAndOrderFront(nil)
    grid.refreshHoveredTile()  // show badges if the panel landed under the cursor

    let ids = windows.map(\.windowID)
    // Stale-but-instant: paint cached last-known frames now; the live capture below
    // replaces them where it succeeds, and leaves them where it can't (off-Space).
    grid.applyThumbnails(thumbnailCache.frames(for: ids))

    let shownSession = machine.session
    Task { [weak self] in
      let captured = await WindowThumbnail.capture(windowIDs: ids)
      guard let self, self.machine.session == shownSession, self.machine.isVisible else { return }
      self.thumbnailCache.remember(captured.images)
      self.grid.applyThumbnails(captured.images)
    }
  }

  private func centerPanel(size: NSSize) {
    // Center on the monitor under the mouse, so the overlay shows where you're looking.
    let mouse = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      ?? NSScreen.main ?? NSScreen.screens.first
    guard let frame = screen?.frame else { return }
    panel.setFrameOrigin(
      NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
  }

  /// The CoreGraphics bounds of the display under the mouse cursor (top-left global
  /// coords, matching CGWindowList bounds). Used to scope the switcher to one monitor.
  private static func monitorUnderMouse() -> CGRect? {
    guard let mouse = CGEvent(source: nil)?.location else { return nil }
    var displayID = CGMainDisplayID()
    var count: UInt32 = 0
    if CGGetDisplaysWithPoint(mouse, 1, &displayID, &count) == .success, count > 0 {
      return CGDisplayBounds(displayID)
    }
    return CGDisplayBounds(CGMainDisplayID())
  }
}
