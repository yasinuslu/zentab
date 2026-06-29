import CoreGraphics
import Testing

@testable import ZenTab

/// Helpers + tests for the stable-list selection cursor that drives the overlay.
@Suite("SwitcherSelection")
struct SwitcherSelectionTests {

  /// Build N synthetic, switchable windows with distinct ids.
  private func windows(_ count: Int) -> [WindowInfo] {
    (0..<count).map { i in
      WindowInfo(
        pid: pid_t(100 + i),
        windowID: CGWindowID(1000 + i),
        title: "Window \(i)",
        appName: "App \(i)",
        frame: CGRect(x: 0, y: 0, width: 400, height: 300),
        isMinimized: false,
        subrole: "AXStandardWindow"
      )
    }
  }

  @Test("Empty list has no selection and ignores navigation")
  func emptyList() {
    var selection = SwitcherSelection()
    #expect(selection.isEmpty)
    #expect(selection.selected == nil)
    selection.selectNext()
    selection.selectPrevious()
    #expect(selection.index == 0)
    #expect(selection.selected == nil)
  }

  @Test("Starts at index 0 by default")
  func startsAtZero() {
    let selection = SwitcherSelection(windows: windows(3))
    #expect(selection.index == 0)
    #expect(selection.selected?.windowID == 1000)
    #expect(selection.lastInput == .keyboard)
  }

  @Test("A custom start index is clamped into range")
  func startIndexClamped() {
    #expect(SwitcherSelection(windows: windows(3), startIndex: 99).index == 2)
    #expect(SwitcherSelection(windows: windows(3), startIndex: -5).index == 0)
  }

  @Test("selectNext advances and wraps")
  func nextWraps() {
    var selection = SwitcherSelection(windows: windows(3))
    selection.selectNext()
    #expect(selection.index == 1)
    selection.selectNext()
    #expect(selection.index == 2)
    selection.selectNext()
    #expect(selection.index == 0)  // wrapped
  }

  @Test("selectPrevious retreats and wraps")
  func previousWraps() {
    var selection = SwitcherSelection(windows: windows(3))
    selection.selectPrevious()
    #expect(selection.index == 2)  // wrapped to last
    selection.selectPrevious()
    #expect(selection.index == 1)
  }

  @Test("Hover moves the cursor and records mouse as last input")
  func hoverWins() {
    var selection = SwitcherSelection(windows: windows(4))
    selection.selectNext()
    #expect(selection.lastInput == .keyboard)
    selection.hover(3)
    #expect(selection.index == 3)
    #expect(selection.lastInput == .mouse)
    // Out-of-range hover is ignored.
    selection.hover(99)
    #expect(selection.index == 3)
  }

  @Test("Keyboard after mouse takes the cursor back (last input wins)")
  func lastInputWins() {
    var selection = SwitcherSelection(windows: windows(4))
    selection.hover(2)
    #expect(selection.lastInput == .mouse)
    selection.selectNext()
    #expect(selection.index == 3)
    #expect(selection.lastInput == .keyboard)
  }
}
