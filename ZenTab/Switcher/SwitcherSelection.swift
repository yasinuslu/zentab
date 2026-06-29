/// The pure selection state machine behind the overlay. It owns a **stable**
/// window list (never reshuffled by recency, per VISION) and a single cursor that
/// both keyboard and mouse drive: whichever moved last wins. No UI, no AppKit —
/// this is the heavily-tested core (the spiritual replacement for the old
/// `FocusModel`).
struct SwitcherSelection: Equatable, Sendable {
  enum InputSource: Sendable { case keyboard, mouse }

  private(set) var windows: [WindowInfo]
  private(set) var index: Int
  /// Which input most recently moved the cursor.
  private(set) var lastInput: InputSource

  init(windows: [WindowInfo] = [], startIndex: Int = 0) {
    self.windows = windows
    self.index = windows.isEmpty ? 0 : Self.clamp(startIndex, count: windows.count)
    self.lastInput = .keyboard
  }

  var isEmpty: Bool { windows.isEmpty }
  var count: Int { windows.count }

  /// The currently-selected window, or nil when the list is empty.
  var selected: WindowInfo? { windows.indices.contains(index) ? windows[index] : nil }

  /// Advance one step forward (Tab), wrapping at the end.
  mutating func selectNext() { advance(by: 1) }

  /// Advance one step backward (Shift+Tab), wrapping at the start.
  mutating func selectPrevious() { advance(by: -1) }

  /// Point the cursor at a hovered tile (mouse). Out-of-range indices are ignored.
  mutating func hover(_ newIndex: Int) {
    guard windows.indices.contains(newIndex) else { return }
    index = newIndex
    lastInput = .mouse
  }

  private mutating func advance(by step: Int) {
    guard !windows.isEmpty else { return }
    let modulo = windows.count
    index = ((index + step) % modulo + modulo) % modulo
    lastInput = .keyboard
  }

  private static func clamp(_ value: Int, count: Int) -> Int {
    min(max(value, 0), count - 1)
  }
}
