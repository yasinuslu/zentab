import AppKit
import Testing

@testable import ZenTab

@Suite("Native hotkey conflict")
struct NativeHotkeyConflictTests {

  @Test("Cmd+Tab claims both the forward AND reverse native switcher")
  func commandTabClaimsBoth() {
    let result = NativeHotkeyConflict.conflicting(with: [Keybinding("cmd+tab")!])
    #expect(result == [.commandTab, .commandShiftTab])
  }

  @Test("Cmd+` claims only the key-above-tab switcher")
  func commandGraveClaimsOnlyItsOwn() {
    let result = NativeHotkeyConflict.conflicting(with: [Keybinding("cmd+`")!])
    #expect(result == [.commandKeyAboveTab])
  }

  @Test("The production suite claims all three native switchers")
  func productionSuiteClaimsAll() {
    let suite = [
      Config.productionDefault.currentApp,
      Config.productionDefault.otherApps,
      Config.productionDefault.everything,
    ]
    #expect(
      NativeHotkeyConflict.conflicting(with: suite)
        == [.commandTab, .commandShiftTab, .commandKeyAboveTab])
  }

  @Test("The development chords collide with no native switcher")
  func developmentSuiteClaimsNothing() {
    let suite = [
      Config.developmentDefault.currentApp,
      Config.developmentDefault.otherApps,
      Config.developmentDefault.everything,
    ]
    #expect(NativeHotkeyConflict.conflicting(with: suite).isEmpty)
  }

  @Test("Option+Tab is not a native switcher, so it claims nothing")
  func optionTabClaimsNothing() {
    #expect(NativeHotkeyConflict.conflicting(with: [Keybinding("opt+tab")!]).isEmpty)
  }

  @Test("Shift is ignored: Cmd+Shift+Tab still resolves to the Cmd+Tab switchers")
  func shiftIsIgnoredInConflictMatching() {
    // Shift is ZenTab's universal reverse modifier, never part of trigger identity.
    let result = NativeHotkeyConflict.conflicting(with: [Keybinding("cmd+shift+tab")!])
    #expect(result == [.commandTab, .commandShiftTab])
  }
}

@Suite("Capture health")
struct CaptureHealthTests {

  @Test("No Accessibility outranks everything")
  func noAccessibility() {
    #expect(
      CaptureHealth.evaluate(accessibilityTrusted: false, tapEnabled: false, stillEnabled: [])
        == .noAccessibility)
  }

  @Test("A trusted-but-disabled tap reports tapDisabled")
  func tapDisabled() {
    #expect(
      CaptureHealth.evaluate(accessibilityTrusted: true, tapEnabled: false, stillEnabled: [])
        == .tapDisabled)
  }

  @Test("A native hotkey that escaped our claim is surfaced")
  func nativeHotkeyEscaped() {
    #expect(
      CaptureHealth.evaluate(
        accessibilityTrusted: true, tapEnabled: true, stillEnabled: [.commandTab])
        == .nativeHotkeyEscaped([.commandTab]))
  }

  @Test("Tap live and nothing escaped means we're capturing")
  func capturing() {
    let health = CaptureHealth.evaluate(
      accessibilityTrusted: true, tapEnabled: true, stillEnabled: [])
    #expect(health == .capturing)
    #expect(health.isCapturing)
    #expect(health.menuBarSymbol == "rectangle.on.rectangle")
  }

  @Test("Any non-capturing state shows the warning icon")
  func warningIconWhenNotCapturing() {
    #expect(CaptureHealth.noAccessibility.menuBarSymbol == "exclamationmark.triangle.fill")
    #expect(CaptureHealth.tapDisabled.menuBarSymbol == "exclamationmark.triangle.fill")
    #expect(!CaptureHealth.tapDisabled.isCapturing)
  }
}

@Suite("Launch profile")
struct LaunchProfileTests {

  @Test("Production profile uses the Cmd+Tab suite")
  func productionDefaults() {
    #expect(LaunchProfile.production.configDefaults == Config.productionDefault)
    #expect(LaunchProfile.production.configDefaults.otherApps == Keybinding("cmd+tab"))
  }

  @Test("Development profile uses the safe chords")
  func developmentDefaults() {
    #expect(LaunchProfile.development.configDefaults == Config.developmentDefault)
    #expect(LaunchProfile.development.configDefaults.otherApps == Keybinding("ctrl+opt+tab"))
  }

  @Test("Config falls back to the supplied profile defaults, not the global default")
  func tomlHonorsProfileDefaults() {
    // Empty TOML + development defaults must yield the dev chords even though the
    // global Config.default is the production suite.
    let config = Config(toml: [:], defaults: .developmentDefault)
    #expect(config == .developmentDefault)
    #expect(config.otherApps == Keybinding("ctrl+opt+tab"))
  }
}
