import Foundation

/// Loads ZenTab's config from `~/.config/zentab/config.toml`, falling back to the
/// bundled default `config.toml`, and finally to `Config.default` if neither is
/// readable. This is the only piece that touches the filesystem; parsing and
/// coercion live in `TOMLParser` / `Config` so they stay testable without IO.
enum ConfigStore {
  /// `~/.config/zentab/config.toml`.
  static var userConfigURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/zentab/config.toml")
  }

  static func load() -> Config {
    guard let text = readUserConfig() ?? readBundledConfig() else {
      return .default
    }
    return Config(toml: TOMLParser.parse(text))
  }

  private static func readUserConfig() -> String? {
    try? String(contentsOf: userConfigURL, encoding: .utf8)
  }

  private static func readBundledConfig() -> String? {
    guard let url = Bundle.main.url(forResource: "config", withExtension: "toml") else {
      return nil
    }
    return try? String(contentsOf: url, encoding: .utf8)
  }
}
