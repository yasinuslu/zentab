import AppKit

/// The overlay window. A borderless, non-activating panel that floats above
/// everything and, crucially, can show and take mouse/keyboard input **without
/// activating ZenTab or stealing key focus** from the app being switched to. That
/// non-activation depends on both `.nonactivatingPanel` here and `LSUIElement` in
/// the Info.plist.
final class SwitcherPanel: NSPanel {
  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: true)

    isFloatingPanel = true
    level = .popUpMenu
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    isOpaque = false
    backgroundColor = .clear
    // The blur lives in the backdrop and the frosted cards are drawn by the grid, so the
    // content panel itself is a clear, shadowless sheet. Pinned dark so the look never
    // depends on the OS light/dark theme (fixes light-mode legibility).
    appearance = OverlayTheme.appearance
    hasShadow = false
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    animationBehavior = .none
    ignoresMouseEvents = false
  }

  // A borderless panel must opt in to becoming key, or it can't receive the mouse
  // hover / keyboard the switcher relies on. It still never activates the app.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
