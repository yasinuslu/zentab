import AppKit
import CoreGraphics

/// A parsed trigger chord, e.g. `"ctrl+opt+tab"` -> (keyCode 48, [.control, .option]).
///
/// Design opinion (matches VISION): **Shift is reserved as the universal "reverse"
/// modifier and is never part of a trigger's identity.** So `ctrl+opt+tab` matches
/// whether or not Shift is also held; the switcher reads Shift separately to decide
/// cycle direction. Only Command / Control / Option distinguish one trigger from
/// another. This whole type is pure and unit-tested.
struct Keybinding: Equatable, Sendable {
  let keyCode: CGKeyCode
  /// The identifying modifiers (a subset of `triggerModifierMask`).
  let modifiers: NSEvent.ModifierFlags

  /// Modifiers that identify a trigger. Shift, CapsLock, Fn, and junk bits are
  /// deliberately excluded so they never affect matching.
  static let triggerModifierMask: NSEvent.ModifierFlags = [.command, .control, .option]

  /// The modifier set whose *release* confirms the switch (the "hold" keys).
  var holdModifiers: NSEvent.ModifierFlags { modifiers.intersection(Self.triggerModifierMask) }

  /// A human-readable glyph form for the overlay header pill, e.g. `⌘ Tab`, `⌃⌥ Tab`,
  /// `⌘ ``. Modifiers use the macOS canonical order (⌃⌥⇧⌘).
  var displayString: String {
    var mods = ""
    if modifiers.contains(.control) { mods += "⌃" }
    if modifiers.contains(.option) { mods += "⌥" }
    if modifiers.contains(.shift) { mods += "⇧" }
    if modifiers.contains(.command) { mods += "⌘" }
    let key = Self.displayLabel(for: keyCode)
    return mods.isEmpty ? key : "\(mods) \(key)"
  }

  /// The display label for a keycode (the reverse of `keyCodes`, with nicer glyphs for the
  /// special keys a trigger realistically uses).
  static func displayLabel(for code: CGKeyCode) -> String {
    switch code {
    case 48: return "Tab"
    case 49: return "Space"
    case 50: return "`"
    case 36: return "↵"
    case 53: return "Esc"
    case 51: return "⌫"
    case 123: return "←"
    case 124: return "→"
    case 125: return "↓"
    case 126: return "↑"
    default:
      if let name = keyCodes.first(where: { $0.value == code && $0.key.count == 1 })?.key {
        return name.uppercased()
      }
      return "?"
    }
  }

  /// Does a live key event satisfy this chord? Identifying modifiers must match
  /// exactly; Shift and other bits are ignored.
  func matches(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags) -> Bool {
    keyCode == self.keyCode
      && modifiers.intersection(Self.triggerModifierMask)
        == self.modifiers.intersection(Self.triggerModifierMask)
  }

  /// Parse a config string like `"ctrl+opt+tab"`. Returns nil if no key token is
  /// present or the key name is unknown. Modifier aliases: cmd/command, opt/option/alt,
  /// ctrl/control, shift. Case- and whitespace-insensitive.
  init?(_ string: String) {
    var mods: NSEvent.ModifierFlags = []
    var key: CGKeyCode?

    for rawToken in string.split(separator: "+") {
      let token = rawToken.trimmingCharacters(in: .whitespaces).lowercased()
      guard !token.isEmpty else { continue }
      switch token {
      case "cmd", "command", "⌘": mods.insert(.command)
      case "opt", "option", "alt", "⌥": mods.insert(.option)
      case "ctrl", "control", "⌃": mods.insert(.control)
      case "shift", "⇧": mods.insert(.shift)
      default:
        // A non-modifier token is the key. Reject a chord with two keys.
        guard key == nil, let code = Self.keyCodes[token] else { return nil }
        key = code
      }
    }

    guard let keyCode = key else { return nil }
    self.keyCode = keyCode
    self.modifiers = mods
  }

  init(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  /// Named key -> ANSI virtual keycode. Covers letters, digits, and the keys a
  /// switcher config realistically uses. Extend as needed.
  static let keyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
    "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
    "0": 29,
    "-": 27, "minus": 27, "=": 24, "equal": 24,
    "[": 33, "]": 30, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44, "\\": 42,
    "`": 50, "grave": 50, "backtick": 50,
    "tab": 48,
    "space": 49,
    "return": 36, "enter": 36,
    "delete": 51, "backspace": 51,
    "escape": 53, "esc": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
  ]
}
