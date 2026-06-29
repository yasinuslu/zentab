import Foundation

/// A deliberately tiny TOML reader covering exactly ZenTab's config grammar:
/// `[section]` headers, `key = "string"`, `key = integer`, and `#` comments.
/// It returns nested `[section: [key: rawValue]]` (values kept as strings; the
/// caller coerces). When the config grows nested tables or arrays, swap this for
/// a real TOML library — until then this stays dependency-free and unit-tested.
enum TOMLParser {
  static func parse(_ text: String) -> [String: [String: String]] {
    var result: [String: [String: String]] = [:]
    var section = ""  // "" is the root table
    result[section] = [:]

    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
      if line.isEmpty { continue }

      if line.hasPrefix("[") && line.hasSuffix("]") {
        section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        if result[section] == nil { result[section] = [:] }
        continue
      }

      guard let eq = line.firstIndex(of: "=") else { continue }
      let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
      guard !key.isEmpty else { continue }
      let value = unquote(
        String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces))
      result[section, default: [:]][key] = value
    }

    return result
  }

  /// Drop everything from the first `#` that is not inside a double-quoted string.
  private static func stripComment(_ line: String) -> String {
    var inQuotes = false
    var output = ""
    for character in line {
      if character == "\"" { inQuotes.toggle() }
      if character == "#" && !inQuotes { break }
      output.append(character)
    }
    return output
  }

  /// Strip a single pair of surrounding double quotes, if present.
  private static func unquote(_ value: String) -> String {
    guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
    return String(value.dropFirst().dropLast())
  }
}
