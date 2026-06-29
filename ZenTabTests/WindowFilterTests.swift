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

  @Test("Dialogs are switchable; other subroles are not")
  func subroleFilter() {
    #expect(WindowInfo.isSwitchable(window(subrole: "AXDialog")))
    #expect(!WindowInfo.isSwitchable(window(subrole: "AXSystemDialog")))
    #expect(!WindowInfo.isSwitchable(window(subrole: "AXUnknown")))
    #expect(!WindowInfo.isSwitchable(window(subrole: "")))
  }

  @Test("Tiny windows are filtered as chrome/helpers")
  func sizeFilter() {
    #expect(!WindowInfo.isSwitchable(window(width: 10, height: 300)))
    #expect(!WindowInfo.isSwitchable(window(width: 400, height: 10)))
    // Exactly at the threshold is allowed.
    #expect(WindowInfo.isSwitchable(window(width: 50, height: 50)))
  }

  @Test("Minimized windows are excluded in the MVP (current-Space, on-screen only)")
  func minimizedExcluded() {
    #expect(!WindowInfo.isSwitchable(window(minimized: true)))
  }
}
