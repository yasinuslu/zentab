/// The three switching scopes from VISION. Behavior is fixed; only the trigger
/// keys are configurable. For the MVP all three are scoped to the current Space
/// (cross-Space / multi-monitor for `everything` is a later milestone).
enum SwitchMode: Sendable {
  /// Cmd+` in the shipped design: windows of the current (frontmost) app only.
  case currentApp
  /// Cmd+Tab: every *other* app's windows (excludes the current app).
  case otherApps
  /// Option+Tab: everything (no app exclusions).
  case everything
}
