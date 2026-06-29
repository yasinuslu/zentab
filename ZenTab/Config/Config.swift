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

  /// Strong defaults so the on-disk config can be near-empty (VISION principle 3).
  /// These are SAFE, non-hijacking dev chords; the native Cmd+Tab / Cmd+` /
  /// Option+Tab override is a later hardening milestone.
  static let `default` = Config(
    currentApp: Keybinding("ctrl+opt+`")!,
    otherApps: Keybinding("ctrl+opt+tab")!,
    everything: Keybinding("ctrl+opt+space")!,
    holdThresholdMs: 150
  )

  /// Build a Config from parsed TOML tables, falling back to `default` per field
  /// so a partial or empty file still yields a complete, valid config.
  init(toml: [String: [String: String]]) {
    let keys = toml["keys"] ?? [:]
    let behavior = toml["behavior"] ?? [:]
    let fallback = Config.default

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
