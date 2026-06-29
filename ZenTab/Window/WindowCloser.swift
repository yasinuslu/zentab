import AppKit
import ApplicationServices

/// Closes a single window or quits a whole app — the in-overlay **W** / **Q** actions.
///
/// Close presses the window's Accessibility close button (the red traffic-light),
/// exactly what a click there does: it closes the window, or for a document app
/// offers to save first. We re-derive the AX window from the registry's cached
/// element (the same cross-Space source `WindowFocuser` uses) and press it **off the
/// main thread**, since AX calls can block. Quit is a polite `terminate()` (the Quit
/// Apple event), so an app with unsaved work can still prompt.
enum WindowCloser {
  private static let queue = DispatchQueue(label: "org.nepjua.ZenTab.close", qos: .userInteractive)

  /// Close one window via its AX close button. No-op for a windowless-app entry
  /// (there is no window) or when no AX element is cached for it.
  @MainActor
  static func close(_ window: WindowInfo) {
    guard !window.isWindowlessApp,
      let axBox = WindowRegistry.shared.axElement(for: window.windowID)
    else { return }
    queue.async { pressCloseButton(axBox.element) }
  }

  /// Quit the app that owns the selected window (every window goes with it).
  @MainActor
  static func quitApp(pid: pid_t) {
    NSRunningApplication(processIdentifier: pid)?.terminate()
  }

  private static func pressCloseButton(_ axWindow: AXUIElement) {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &value)
        == .success,
      let value, CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return }
    let closeButton = unsafeDowncast(value, to: AXUIElement.self)
    AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
  }
}
