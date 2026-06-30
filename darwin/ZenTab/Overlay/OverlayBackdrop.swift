import AppKit

/// The dim + blur scrim behind the switcher: VISION's "the rest of the world recedes."
/// One borderless, click-through panel per monitor, each a dark `NSVisualEffectView`
/// blur with a dimming layer over it. The scrim fades in the instant the overlay is
/// summoned and out when it commits/cancels, so the world softly steps back and forward.
///
/// The panels are **click-through** (`ignoresMouseEvents`): a click on the dimmed world
/// still lands on whatever is under it, and the global click-watch in `OverlayController`
/// is what turns that click into a cancel — preserving VISION's "click outside still lands
/// on what's beneath; we only stop switching."
@MainActor
final class OverlayBackdrop {
  /// Sits just under the interactive content panel, above every ordinary window.
  static let level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)

  private var panels: [BackdropPanel] = []
  private var builtForFrames: [CGRect] = []

  /// Fade the scrim in across every monitor. Rebuilds the panels only when the monitor
  /// layout actually changed, so a normal summon just re-shows the cached panels.
  func show() {
    rebuildIfScreensChanged()
    for panel in panels {
      panel.alphaValue = 0
      panel.orderFront(nil)
      NSAnimationContext.runAnimationGroup { context in
        context.duration = OverlayTheme.fadeDuration
        context.allowsImplicitAnimation = true
        panel.animator().alphaValue = 1
      }
    }
  }

  /// Fade the scrim out, then order the panels away once they're invisible.
  func hide() {
    for panel in panels {
      NSAnimationContext.runAnimationGroup(
        { context in
          context.duration = OverlayTheme.fadeDuration
          panel.animator().alphaValue = 0
        },
        completionHandler: { [weak panel] in panel?.orderOut(nil) })
    }
  }

  /// Tear the scrim away with no fade (used when a summon supersedes a visible overlay).
  func hideImmediately() {
    for panel in panels {
      panel.alphaValue = 0
      panel.orderOut(nil)
    }
  }

  private func rebuildIfScreensChanged() {
    let frames = NSScreen.screens.map(\.frame)
    guard frames != builtForFrames else { return }
    panels.forEach { $0.orderOut(nil) }
    panels = frames.map { BackdropPanel(frame: $0) }
    builtForFrames = frames
  }
}

/// One monitor's scrim: a forced-dark blur with a dim layer on top. Never takes the mouse.
private final class BackdropPanel: NSPanel {
  init(frame: CGRect) {
    super.init(
      contentRect: frame, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered,
      defer: false)
    appearance = OverlayTheme.appearance
    level = OverlayBackdrop.level
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    ignoresMouseEvents = true
    isReleasedWhenClosed = false
    animationBehavior = .none
    hidesOnDeactivate = false

    let blur = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
    blur.material = OverlayTheme.Backdrop.material
    blur.blendingMode = .behindWindow
    blur.state = .active
    blur.autoresizingMask = [.width, .height]
    blur.wantsLayer = true

    // The website's atmosphere baked into the scrim: a cool near-black radial gradient that
    // lifts toward the top-left, near-opaque so the spotlight reads the same dark over any
    // wallpaper. See OverlayTheme.Backdrop.
    let dim = CAGradientLayer()
    dim.type = .radial
    dim.frame = blur.bounds
    dim.colors = [OverlayTheme.Backdrop.dimInner.cgColor, OverlayTheme.Backdrop.dimOuter.cgColor]
    dim.startPoint = OverlayTheme.Backdrop.dimCenter
    dim.endPoint = OverlayTheme.Backdrop.dimEdge
    dim.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    blur.layer?.addSublayer(dim)

    contentView = blur
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
