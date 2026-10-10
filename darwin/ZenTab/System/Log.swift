import os

/// ZenTab's own unified-log channels. Everything here logs at `notice` (or above) so it
/// is persisted and still readable after the fact — the shortcut dying "out of nowhere"
/// is only diagnosable from what was written before the user noticed:
///
///     log show --last 2h --predicate 'subsystem == "org.nepjua.ZenTab"'
enum Log {
  private static let subsystem = "org.nepjua.ZenTab"
  /// The event tap, its watchdog, capture health, Secure Input.
  static let input = Logger(subsystem: subsystem, category: "input")
  /// Bringing the chosen window forward.
  static let focus = Logger(subsystem: subsystem, category: "focus")
}
