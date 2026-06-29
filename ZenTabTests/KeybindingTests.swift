import AppKit
import Testing

@testable import ZenTab

@Suite("Keybinding")
struct KeybindingTests {

  @Test("Parses a modifier chord into keycode + identifying modifiers")
  func parsesChord() {
    let binding = Keybinding("ctrl+opt+tab")
    #expect(binding?.keyCode == 48)
    #expect(binding?.modifiers == [.control, .option])
  }

  @Test("Modifier aliases and case/whitespace are normalized")
  func aliases() {
    #expect(Keybinding("Cmd + Shift + A")?.modifiers == [.command, .shift])
    #expect(Keybinding("command+shift+a")?.keyCode == 0)
    #expect(Keybinding("ALT+`")?.modifiers == [.option])
    #expect(Keybinding("control+option+tab") == Keybinding("ctrl+opt+tab"))
  }

  @Test("A chord with no key, or an unknown key, fails to parse")
  func rejectsBadInput() {
    #expect(Keybinding("ctrl+opt") == nil)  // modifiers only
    #expect(Keybinding("ctrl+opt+nope") == nil)  // unknown key
    #expect(Keybinding("ctrl+a+b") == nil)  // two keys
    #expect(Keybinding("") == nil)
  }

  @Test("matches requires exact cmd/ctrl/opt but ignores shift")
  func matchingIgnoresShift() {
    let binding = Keybinding("ctrl+opt+tab")!
    #expect(binding.matches(keyCode: 48, modifiers: [.control, .option]))
    // Shift is the reverse modifier, never part of identity:
    #expect(binding.matches(keyCode: 48, modifiers: [.control, .option, .shift]))
    // CapsLock / junk bits are ignored too:
    #expect(binding.matches(keyCode: 48, modifiers: [.control, .option, .capsLock]))
  }

  @Test("matches rejects wrong key or missing/extra identifying modifiers")
  func matchingRejects() {
    let binding = Keybinding("ctrl+opt+tab")!
    #expect(!binding.matches(keyCode: 53, modifiers: [.control, .option]))  // wrong key
    #expect(!binding.matches(keyCode: 48, modifiers: [.control]))  // missing option
    #expect(!binding.matches(keyCode: 48, modifiers: [.control, .option, .command]))  // extra cmd
  }

  @Test("holdModifiers strips everything but the identifying modifiers")
  func holdModifiers() {
    let binding = Keybinding(keyCode: 48, modifiers: [.control, .option, .shift])
    #expect(binding.holdModifiers == [.control, .option])
  }
}
