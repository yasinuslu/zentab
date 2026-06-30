import Foundation

/// Which trigger-key suite ZenTab launches with. The released app and `bin/run-prod`
/// use `.production` (the real Cmd+Tab three-shortcut design, which replaces the
/// native macOS switchers); `bin/run` passes `-profile dev` so day-to-day
/// development uses safe chords that never touch the user's Cmd+Tab.
///
/// Selected via the `-profile` launch argument, which lands in `UserDefaults`'
/// argument domain (e.g. `open ZenTab.app --args -profile dev`). Absent ⇒ production,
/// so a normal double-click of the app gets the shipped suite.
enum LaunchProfile: String {
  case development
  case production

  static var current: LaunchProfile {
    switch UserDefaults.standard.string(forKey: "profile")?.lowercased() {
    case "dev", "development": return .development
    default: return .production
    }
  }

  /// The compiled-in defaults this profile falls back to (config.toml overrides win).
  var configDefaults: Config {
    switch self {
    case .development: return .developmentDefault
    case .production: return .productionDefault
    }
  }

  /// Human-readable label for the menu bar.
  var label: String {
    switch self {
    case .development: return "Development"
    case .production: return "Production"
    }
  }
}
