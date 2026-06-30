import Foundation

/// ZenTab's runtime configuration. Per VISION, the switching *behavior* is fixed;
/// only the trigger keys (and the tap-vs-hold threshold) are configurable. Pure
/// value type, no file IO — `ConfigStore` does the reading and hands the parsed
/// TOML tables to `init(toml:)`.
struct Config: Sendable, Equatable {
  /// Cmd+` in the shipped design: windows of the current app.
  var currentApp: Keybinding
  /// Cmd+Tab in the shipped design: other apps' windows. The MVP wires THIS one.
  var otherApps: Keybinding
  /// Option+Tab in the shipped design: everything, everywhere.
  var everything: Keybinding
  /// Overlay appears after the trigger modifier is held this long; a faster tap
  /// switches with no overlay at all.
  var holdThresholdMs: Int

  /// The hold threshold as seconds, for `DispatchQueue.asyncAfter`.
  var holdThreshold: TimeInterval { Double(holdThresholdMs) / 1000.0 }

  init(currentApp: Keybinding, otherApps: Keybinding, everything: Keybinding, holdThresholdMs: Int) {
    self.currentApp = currentApp
    self.otherApps = otherApps
    self.everything = everything
    self.holdThresholdMs = holdThresholdMs
  }

  /// The shipped suite (VISION's three-shortcut model): ZenTab owns Cmd+Tab and
  /// Cmd+`, replacing the native switchers. This is the default for the released app
  /// and `bin/run-prod`; the capture watchdog keeps the claim reliable.
  static let productionDefault = Config(
    currentApp: Keybinding("cmd+`")!,
    otherApps: Keybinding("cmd+tab")!,
    everything: Keybinding("opt+tab")!,
    holdThresholdMs: 150
  )

  /// SAFE, non-hijacking chords for day-to-day development (`bin/run`): they never
  /// touch the native Cmd+Tab, so iterating on the app can't strand your switcher.
  static let developmentDefault = Config(
    currentApp: Keybinding("ctrl+opt+`")!,
    otherApps: Keybinding("ctrl+opt+tab")!,
    // Not Space: Ctrl+Opt+Space is macOS "select next input source".
    everything: Keybinding("ctrl+opt+a")!,
    holdThresholdMs: 150
  )

  /// The fallback for config that doesn't specify a profile (and the shipped app's
  /// out-of-box behavior): the production Cmd+Tab suite.
  static let `default` = productionDefault

  /// Build a Config from parsed TOML tables, falling back to `defaults` per field so
  /// a partial or empty file still yields a complete, valid config. `defaults` is the
  /// launch profile's suite (production unless `bin/run` selected development).
  init(toml: [String: [String: String]], defaults: Config = .default) {
    let keys = toml["keys"] ?? [:]
    let behavior = toml["behavior"] ?? [:]
    let fallback = defaults

    func binding(_ name: String, _ fallbackBinding: Keybinding) -> Keybinding {
      if let raw = keys[name], let parsed = Keybinding(raw) { return parsed }
      return fallbackBinding
    }

    currentApp = binding("current_app", fallback.currentApp)
    otherApps = binding("other_apps", fallback.otherApps)
    everything = binding("everything", fallback.everything)

    if let raw = behavior["hold_threshold_ms"], let value = Int(raw), value >= 0 {
      holdThresholdMs = value
    } else {
      holdThresholdMs = fallback.holdThresholdMs
    }
  }
}
