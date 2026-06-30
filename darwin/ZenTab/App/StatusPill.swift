import AppKit

/// A tiny capsule that floats just under the notch to tell Yasin whether it's safe to touch
/// the machine while ZenTab is being driven for screenshots/iteration:
///   • **red** — testing in progress, hands off (the screen is being driven).
///   • **green** — done, safe to use.
///
/// It's a dev affordance only (wired behind the development profile) and is driven from a
/// shell via a small status file (`~/.zentab-test-status`) so an automated test loop can
/// flip it red before it starts and green when it finishes. Floats above the overlay so it
/// stays visible even while the preview is up; never takes the mouse.
@MainActor
final class StatusPill {
  /// The status file an external test loop writes: `busy`/`red` → red, `ready`/`green`/`done`
  /// → green, missing/empty → hidden.
  static let statusFilePath = (NSHomeDirectory() as NSString).appendingPathComponent(
    ".zentab-test-status")

  private let panel: NSPanel
  private let capsule = CALayer()
  private let dot = CALayer()
  private let label = CATextLayer()
  private var pollTimer: Timer?
  private var lastValue: String?

  init() {
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 230, height: 30),
      styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
    panel.appearance = OverlayTheme.appearance
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.ignoresMouseEvents = true
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.animationBehavior = .none

    let host = NSView(frame: panel.contentLayoutRect)
    host.wantsLayer = true
    capsule.frame = host.bounds
    capsule.cornerRadius = 15
    capsule.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
    capsule.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
    capsule.borderWidth = 1
    dot.frame = CGRect(x: 16, y: 11, width: 8, height: 8)
    dot.cornerRadius = 4
    capsule.addSublayer(dot)
    label.frame = CGRect(x: 32, y: 8, width: 186, height: 15)
    label.fontSize = 11
    label.alignmentMode = .left
    label.contentsScale = OverlayTheme.textScale
    label.foregroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
    capsule.addSublayer(label)
    host.layer?.addSublayer(capsule)
    panel.contentView = host
  }

  /// Poll the status file so a shell test loop can flip the light without an IPC dance.
  func startWatching() {
    apply(readStatus())
    pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.apply(self.readStatus())
      }
    }
  }

  private func readStatus() -> String {
    (try? String(contentsOfFile: Self.statusFilePath, encoding: .utf8))?
      .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
  }

  private func apply(_ value: String) {
    guard value != lastValue else { return }
    lastValue = value
    switch value {
    case "busy", "red", "testing":
      show(color: .systemRed, text: "ZenTab testing — hands off")
    case "ready", "green", "done", "safe":
      show(color: .systemGreen, text: "ZenTab — safe to use")
    default:
      panel.orderOut(nil)
    }
  }

  private func show(color: NSColor, text: String) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    dot.backgroundColor = color.cgColor
    dot.shadowColor = color.cgColor
    dot.shadowOpacity = 0.9
    dot.shadowRadius = 5
    dot.shadowOffset = .zero
    label.string = text
    CATransaction.commit()
    positionUnderNotch()
    panel.orderFront(nil)
  }

  /// Center the pill horizontally and tuck it just below the notch / menu bar.
  private func positionUnderNotch() {
    guard let screen = NSScreen.main else { return }
    let size = panel.frame.size
    let x = screen.frame.midX - size.width / 2
    let y = screen.frame.maxY - size.height - 38  // clear of the ~37 px notch/menu-bar band
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }
}
