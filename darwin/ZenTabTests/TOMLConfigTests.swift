import Testing

@testable import ZenTab

@Suite("TOML + Config")
struct TOMLConfigTests {

  @Test("Parses sections, strings, ints, and comments")
  func parsesGrammar() {
    let toml = """
      # a comment line
      [keys]
      other_apps = "ctrl+opt+tab"   # trailing comment
      current_app = "cmd+`"

      [behavior]
      hold_threshold_ms = 200
      """
    let tables = TOMLParser.parse(toml)
    #expect(tables["keys"]?["other_apps"] == "ctrl+opt+tab")
    #expect(tables["keys"]?["current_app"] == "cmd+`")
    #expect(tables["behavior"]?["hold_threshold_ms"] == "200")
  }

  @Test("A # inside quotes is not treated as a comment")
  func hashInsideQuotes() {
    let tables = TOMLParser.parse(#"key = "a # b""#)
    #expect(tables[""]?["key"] == "a # b")
  }

  @Test("Config from full TOML overrides every default")
  func configOverrides() {
    let tables = TOMLParser.parse(
      """
      [keys]
      current_app = "cmd+1"
      other_apps = "cmd+2"
      everything = "cmd+3"
      [behavior]
      hold_threshold_ms = 250
      """)
    let config = Config(toml: tables)
    #expect(config.currentApp == Keybinding("cmd+1"))
    #expect(config.otherApps == Keybinding("cmd+2"))
    #expect(config.everything == Keybinding("cmd+3"))
    #expect(config.holdThresholdMs == 250)
  }

  @Test("Missing or invalid values fall back to defaults")
  func partialFallsBack() {
    let tables = TOMLParser.parse(
      """
      [keys]
      other_apps = "cmd+9"
      [behavior]
      hold_threshold_ms = "not a number"
      """)
    let config = Config(toml: tables)
    #expect(config.otherApps == Keybinding("cmd+9"))  // overridden
    #expect(config.currentApp == Config.default.currentApp)  // default
    #expect(config.everything == Config.default.everything)  // default
    #expect(config.holdThresholdMs == Config.default.holdThresholdMs)  // invalid -> default
  }

  @Test("An empty file yields the full default config")
  func emptyIsDefault() {
    #expect(Config(toml: TOMLParser.parse("")) == Config.default)
  }

  @Test("holdThreshold converts milliseconds to seconds")
  func thresholdSeconds() {
    #expect(Config.default.holdThreshold == 0.150)
  }
}
