import AppKit

/// The main-actor coordinator between input, model, and view. It receives
/// summon/cycle/confirm/cancel from `HotkeyTap` and:
///
/// - enumerates windows off-main, then builds a stable `SwitcherSelection`;
/// - implements tap-vs-hold: the panel is only shown after the hold threshold, so a
///   fast tap focuses the first window with no overlay at all;
/// - drives the `TileGridView` and focuses the selection on confirm.
///
/// A monotonically increasing `session` id guards against stale async results from a
/// previous summon landing on the current one.
@MainActor
final class OverlayController {
  private let config: Config
  private let panel = SwitcherPanel()
  private let grid = TileGridView(frame: .zero)

  private var selection = SwitcherSelection()
  private var session = 0
  private var enumerated = false
  private var showRequested = false
  private var pendingConfirm = false
  private var pendingSteps = 0
  private var isVisible = false

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

    grid.onHover = { [weak self] index in self?.hover(index) }
    grid.onActivate = { [weak self] index in
      self?.hover(index)
      self?.confirm()
    }
  }

  // MARK: - HotkeyTap handlers

  func summon() {
    session += 1
    let current = session
    enumerated = false
    showRequested = false
    pendingConfirm = false
    pendingSteps = 0
    selection = SwitcherSelection()

    let excluded = excludedPIDs()
    Task { [weak self] in
      let windows = await WindowEnumerator.enumerate(excludingPIDs: excluded)
      self?.onEnumerated(windows, session: current)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + config.holdThreshold) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.session == current else { return }
        self.showRequested = true
        self.showPanelIfReady()
      }
    }
  }

  func cycle(backward: Bool) {
    guard enumerated else {
      pendingSteps += backward ? -1 : 1
      return
    }
    if backward { selection.selectPrevious() } else { selection.selectNext() }
    grid.updateSelection(selection.index)
  }

  func confirm() {
    guard enumerated else {
      pendingConfirm = true
      return
    }
    let target = selection.selected
    hide()
    if let target { WindowFocuser.focus(target) }
  }

  func cancel() {
    pendingConfirm = false
    hide()
  }

  // MARK: - Internal flow

  private func onEnumerated(_ windows: [WindowInfo], session current: Int) {
    guard session == current else { return }  // a newer summon superseded this one
    enumerated = true

    let start: Int
    if windows.isEmpty {
      start = 0
    } else {
      let modulo = windows.count
      start = ((pendingSteps % modulo) + modulo) % modulo
    }
    selection = SwitcherSelection(windows: windows, startIndex: start)
    pendingSteps = 0

    if pendingConfirm {
      pendingConfirm = false
      let target = selection.selected
      hide()
      if let target { WindowFocuser.focus(target) }
      return
    }
    showPanelIfReady()
  }

  private func showPanelIfReady() {
    guard showRequested, enumerated, !isVisible, !selection.isEmpty else { return }

    let current = session
    let size = grid.configure(windows: selection.windows, selectedIndex: selection.index)
    panel.setContentSize(size)
    centerPanel(size: size)
    panel.makeKeyAndOrderFront(nil)
    isVisible = true

    let ids = selection.windows.map(\.windowID)
    Task { [weak self] in
      let captured = await WindowThumbnail.capture(windowIDs: ids)
      guard let self, self.session == current, self.isVisible else { return }
      self.grid.applyThumbnails(captured.images)
    }
  }

  private func hover(_ index: Int) {
    selection.hover(index)
    grid.updateSelection(selection.index)
  }

  private func hide() {
    panel.orderOut(nil)
    isVisible = false
    showRequested = false
  }

  private func centerPanel(size: NSSize) {
    let screen = NSScreen.main ?? NSScreen.screens.first
    guard let frame = screen?.frame else { return }
    panel.setFrameOrigin(
      NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
  }

  /// Exclude ZenTab itself and the current (frontmost) app: "other apps" mode.
  private func excludedPIDs() -> Set<pid_t> {
    var excluded: Set<pid_t> = [ProcessInfo.processInfo.processIdentifier]
    if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier {
      excluded.insert(front)
    }
    return excluded
  }
}
