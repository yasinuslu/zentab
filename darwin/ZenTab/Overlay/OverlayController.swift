import AppKit

/// The main-actor shell around `OverlaySession`. It owns the AppKit overlay — the dim+blur
/// backdrop and the full-screen content panel — and the real side effects (off-main
/// enumeration, the hold timer, thumbnail capture, focus), but holds **no decision logic**:
/// every input is fed to the pure `OverlaySession`, and whatever `Effect`s it returns are
/// executed here. That keeps the tricky tap-vs-hold / confirm-wins / stale-timer behavior in
/// a unit-tested value type.
///
/// The overlay is two layers: a click-through `OverlayBackdrop` (the world dims + blurs) and
/// a transparent, full-active-screen content panel hosting the `TileGridView`. The grid
/// draws its own frosted cards over the blurred backdrop, so the content panel itself is
/// clear. A click on a tile activates; a click on the dimmed void (or another monitor)
/// cancels — VISION's one cancel gesture.
@MainActor
final class OverlayController {
  private let config: Config
  private let panel = SwitcherPanel()
  private let grid = TileGridView(frame: .zero)
  private let backdrop = OverlayBackdrop()
  private var machine = OverlaySession()
  /// Last-known frame per window, so off-Space / off-monitor windows (which can't be
  /// captured live) still show their latest thumbnail instead of a bare icon.
  private let thumbnailCache = ThumbnailCache()
  /// Keeps the cache warm so a summon paints a recent frame instantly. On-screen
  /// windows only, gently paced, and paused under Low Power to respect the battery.
  private var refreshTimer: Timer?
  /// Global mouse-down watch, live only while the overlay is up: a click on another monitor
  /// (outside the content panel) cancels the switcher. The click still lands on whatever is
  /// under it (the backdrop is click-through); we only stop switching.
  private var clickOutsideMonitor: Any?
  /// Guards the hide fade-out's `orderOut` against a fast re-summon (see `hidePanel`).
  private var showGeneration = 0

  // Captured at each summon so the enumeration effect knows what to ask for.
  private var pendingMode: SwitchMode = .otherApps
  private var pendingFrontmostPID: pid_t?
  private var pendingSelfPID: pid_t = 0
  private var pendingMonitorFrame: CGRect?

  init(config: Config) {
    self.config = config
    panel.contentView = grid

    grid.onHover = { [weak self] index in self?.send(.hover(index)) }
    grid.onActivate = { [weak self] index in
      self?.send(.hover(index))
      self?.send(.confirm)
    }
    grid.onCancel = { [weak self] in
      guard let self else { return }
      if self.previewActive { self.dismissPreview() } else { self.send(.cancel) }
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
    // The "↓ here" chip summons an elsewhere window to the current Space.
    grid.onSummon = { [weak self] index in
      self?.send(.hover(index))
      self?.send(.summonSelected)
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
        guard let self else { return }
        // The board (here/elsewhere split) is for the multi-Space modes; Cmd+Tab is current-
        // Space only, so it stays a flat list. "Here" = the windows on the current Space.
        let usesBoard = mode != .otherApps
        let hereIDs = usesBoard ? SpaceMover.windowsOnCurrentSpace() : []
        self.send(
          .enumerated(windows, hereIDs: hereIDs, usesBoard: usesBoard, currentPID: frontmost, session: id))
      }

    case .scheduleHold(let id):
      DispatchQueue.main.asyncAfter(deadline: .now() + config.holdThreshold) { [weak self] in
        MainActor.assumeIsolated { self?.send(.holdElapsed(session: id)) }
      }

    case .show(let windows, let hereStart, let index):
      showPanel(windows: windows, hereStart: hereStart, index: index)

    case .updateSelection(let index):
      grid.updateSelection(index)

    case .relayout(let windows, let hereStart, let index):
      relayoutPanel(windows: windows, hereStart: hereStart, index: index)
      consumeFly()

    case .hide:
      hidePanel()
      consumeFly()  // drop any pending ghost (e.g. flinging the last window)
      removeClickOutsideDismissal()

    case .focus(let window):
      if let window { WindowFocuser.focus(window) }

    case .close(let window):
      WindowCloser.close(window)

    case .quit(let pid):
      WindowCloser.quitApp(pid: pid)

    case .summonWindow(let window):
      SpaceMover.summon(window)
      // Snapshot the tile NOW (old layout); the .relayout that follows flies it down to HERE.
      grid.beginGhost(windowID: window.windowID)
      pendingFly = .toHere(window.windowID)

    case .flingWindow(let window, let direction):
      SpaceMover.fling(window, direction)
      grid.beginGhost(windowID: window.windowID)
      pendingFly = .off(direction)
    }
  }

  /// A queued fly animation, captured on a move effect and run on the relayout that follows.
  private enum FlyIntent {
    case toHere(CGWindowID)
    case off(FlingDirection)
  }
  private var pendingFly: FlyIntent?

  private func consumeFly() {
    switch pendingFly {
    case .toHere(let windowID): grid.flyGhostToHere(windowID: windowID)
    case .off(let direction): grid.flyGhostOff(direction: direction)
    case nil: break
    }
    pendingFly = nil
  }

  // MARK: - Click-outside-to-cancel

  /// Watch global mouse-downs while the overlay is up; a click on another monitor (outside
  /// the active content panel) cancels the switcher (dismiss, no focus change). Clicks on the
  /// active monitor are handled by the grid itself (tile = activate, void = cancel). Idempotent.
  private func installClickOutsideDismissal() {
    guard clickOutsideMonitor == nil else { return }
    clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.machine.isVisible else { return }
        if !self.panel.frame.contains(NSEvent.mouseLocation) { self.send(.cancel) }
      }
    }
  }

  private func removeClickOutsideDismissal() {
    if let clickOutsideMonitor { NSEvent.removeMonitor(clickOutsideMonitor) }
    clickOutsideMonitor = nil
  }

  // MARK: - Panel show / relayout / hide

  /// Re-lay the grid after a move/close/quit changed the list, keeping the live thumbnails
  /// already captured for the survivors (no re-capture). The panel already fills the screen,
  /// so only the grid content changes.
  private func relayoutPanel(windows: [WindowInfo], hereStart: Int, index: Int) {
    grid.configure(windows: windows, hereStart: hereStart, selectedIndex: index, keepThumbnails: true)
    grid.refreshHoveredTile()  // the survivors shifted under the cursor; re-place badges
  }

  private func showPanel(windows: [WindowInfo], hereStart: Int, index: Int) {
    frameToActiveScreen()
    grid.configure(
      windows: windows, hereStart: hereStart, selectedIndex: index,
      header: headerInfo(mode: pendingMode, windows: windows))

    backdrop.show()
    showGeneration += 1
    panel.alphaValue = 0
    panel.makeKeyAndOrderFront(nil)
    grid.playSummon()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = OverlayTheme.fadeDuration
      panel.animator().alphaValue = 1
    }
    installClickOutsideDismissal()
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

  /// Fade the overlay out. The `orderOut` is gated on `showGeneration` so a fast re-summon
  /// (which bumps the generation before this fade completes) never orders the new panel away.
  private func hidePanel() {
    backdrop.hide()
    let generation = showGeneration
    NSAnimationContext.runAnimationGroup(
      { context in
        context.duration = OverlayTheme.fadeDuration
        panel.animator().alphaValue = 0
      },
      completionHandler: { [weak self] in
        guard let self, self.showGeneration == generation else { return }
        self.panel.orderOut(nil)
      })
  }

  /// The header strip's contents for a mode: the trigger-key glyphs (from the live config,
  /// so it's truthful about what's actually bound) and the mode label (matching the website).
  private func headerInfo(mode: SwitchMode, windows: [WindowInfo]) -> TileGridView.Header {
    let key: String
    switch mode {
    case .currentApp: key = config.currentApp.displayString
    case .otherApps: key = config.otherApps.displayString
    case .everything: key = config.everything.displayString
    }
    let label: String
    switch mode {
    case .otherApps: label = "All windows · this display"
    case .currentApp: label = (windows.first?.appName ?? "Current app") + " · every window, everywhere"
    case .everything: label = "Everything, everywhere"
    }
    return TileGridView.Header(key: key, label: label)
  }

  /// Size the content panel to the monitor under the mouse, so the overlay shows where
  /// you're looking. The backdrop covers every monitor on its own.
  private func frameToActiveScreen() {
    let mouse = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      ?? NSScreen.main ?? NSScreen.screens.first
    guard let frame = screen?.frame else { return }
    panel.setFrame(frame, display: false)
  }

  // MARK: - Dev preview (no hotkey / state machine)

  /// True while a `preview(board:)` overlay is on screen. Lets the void-click cancel route
  /// to `dismissPreview` instead of the (inactive) state machine.
  private var previewActive = false

  /// Show the redesigned overlay populated from the running apps, bypassing the hotkey and
  /// state machine, so the look can be screenshotted/iterated without holding a modifier.
  /// `board` true → the two-zone ELSEWHERE/HERE board; false → the flat everyday grid.
  /// Click the dimmed void to dismiss. Dev-only (wired behind the development menu).
  func preview(board: Bool) {
    if previewActive { dismissPreview() }
    let apps = NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular && $0.icon != nil }
    let sample = apps.prefix(11).enumerated().map { offset, app -> WindowInfo in
      WindowInfo(
        pid: app.processIdentifier, windowID: CGWindowID(90000 + offset),
        title: app.localizedName ?? "Window", appName: app.localizedName ?? "App",
        frame: .zero, isMinimized: false, subrole: "AXStandardWindow")
    }
    guard !sample.isEmpty else { return }
    // Leave ~3 windows in HERE so both zones populate (the rest go to ELSEWHERE).
    let hereStart = board ? max(1, sample.count - 3) : 0

    previewActive = true
    frameToActiveScreen()
    let previewHeader = TileGridView.Header(
      key: board ? "⌥ Tab" : "⌘ Tab",
      label: board ? "Everything, everywhere" : "All windows · this display")
    grid.configure(windows: sample, hereStart: hereStart, selectedIndex: 0, header: previewHeader)
    backdrop.show()
    showGeneration += 1
    panel.alphaValue = 0
    panel.makeKeyAndOrderFront(nil)
    grid.playSummon()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = OverlayTheme.fadeDuration
      panel.animator().alphaValue = 1
    }
    grid.refreshHoveredTile()
  }

  /// Toggle the preview on/off (used by the `SIGUSR2` hook so it can be driven from a shell
  /// for screenshots without holding a hotkey).
  func togglePreview(board: Bool) {
    if previewActive { dismissPreview() } else { preview(board: board) }
  }

  private func dismissPreview() {
    previewActive = false
    hidePanel()
  }

  // MARK: - Geometry

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
