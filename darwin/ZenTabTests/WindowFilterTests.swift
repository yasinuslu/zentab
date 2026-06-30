import CoreGraphics
import Testing

@testable import ZenTab

@Suite("WindowInfo.isSwitchable")
struct WindowFilterTests {

  private func window(
    subrole: String = "AXStandardWindow",
    width: CGFloat = 400,
    height: CGFloat = 300,
    minimized: Bool = false
  ) -> WindowInfo {
    WindowInfo(
      pid: 123,
      windowID: 1,
      title: "t",
      appName: "App",
      frame: CGRect(x: 0, y: 0, width: width, height: height),
      isMinimized: minimized,
      subrole: subrole
    )
  }

  @Test("A normal standard window is switchable")
  func standardIsSwitchable() {
    #expect(WindowInfo.isSwitchable(window()))
  }

  @Test("Real windows pass (denylist); only explicit non-windows are rejected")
  func subroleFilter() {
    // Standard, dialog, unknown, and empty subroles are all treated as real
    // windows — reliability over precision, so odd-reporting apps aren't dropped.
    #expect(WindowInfo.isSwitchable(window(subrole: "AXStandardWindow")))
    #expect(WindowInfo.isSwitchable(window(subrole: "AXDialog")))
    #expect(WindowInfo.isSwitchable(window(subrole: "AXUnknown")))
    #expect(WindowInfo.isSwitchable(window(subrole: "")))
    // Explicit palettes / floating tool windows / system dialogs are not switchable.
    #expect(!WindowInfo.isSwitchable(window(subrole: "AXFloatingWindow")))
    #expect(!WindowInfo.isSwitchable(window(subrole: "AXSystemFloatingWindow")))
    #expect(!WindowInfo.isSwitchable(window(subrole: "AXSystemDialog")))
  }

  @Test("Tiny windows are filtered as chrome/helpers")
  func sizeFilter() {
    #expect(!WindowInfo.isSwitchable(window(width: 10, height: 300)))
    #expect(!WindowInfo.isSwitchable(window(width: 400, height: 10)))
    // Exactly at the threshold is allowed.
    #expect(WindowInfo.isSwitchable(window(width: 50, height: 50)))
  }

  @Test("Minimized windows are excluded by default (current-app / other-apps modes)")
  func minimizedExcludedByDefault() {
    #expect(!WindowInfo.isSwitchable(window(minimized: true)))
  }

  @Test("Minimized windows are included for the everything mode")
  func minimizedIncludedWhenAsked() {
    #expect(WindowInfo.isSwitchable(window(minimized: true), includeMinimized: true))
  }

  @Test("isOnMonitor keeps windows whose center is on the given monitor")
  func monitorFilter() {
    let w = window()  // frame 0,0,400,300 -> center (200,150)
    #expect(w.isOnMonitor(nil))  // nil = no filtering (everything mode)
    #expect(w.isOnMonitor(CGRect(x: 0, y: 0, width: 1440, height: 900)))  // this monitor
    #expect(!w.isOnMonitor(CGRect(x: 1440, y: 0, width: 1440, height: 900)))  // the other monitor
  }

  @Test("A minimized window passes even with an unreliable zero AX size")
  func minimizedSkipsSizeGate() {
    let zeroSized = window(width: 0, height: 0, minimized: true)
    #expect(WindowInfo.isSwitchable(zeroSized, includeMinimized: true))
    // ...but an explicit non-window (a floating palette) is still rejected.
    let palette = WindowInfo(
      pid: 1, windowID: 1, title: "t", appName: "A",
      frame: .zero, isMinimized: true, subrole: "AXFloatingWindow")
    #expect(!WindowInfo.isSwitchable(palette, includeMinimized: true))
  }
}
