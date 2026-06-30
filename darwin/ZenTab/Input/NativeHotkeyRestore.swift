import AppKit

/// Last-resort restoration of the native macOS symbolic hotkeys ZenTab can disable,
/// so a crash or a `kill` never leaves the user with a dead Cmd+Tab. The symbolic
/// hotkey state persists after our process exits, so on graceful quit `AppModel`
/// restores it explicitly — these handlers cover the paths that skip `terminate`.
///
/// Re-enabling an already-enabled hotkey is a harmless no-op, so the handlers (which
/// can't safely carry runtime state) just restore the whole set ZenTab ever manages.
enum NativeHotkeyRestore {
  /// Every symbolic hotkey any launch profile can disable.
  private static let everManaged: [SymbolicHotkey] = [
    .commandTab, .commandShiftTab, .commandKeyAboveTab,
  ]

  static func restoreAll() {
    for hotkey in everManaged {
      CGSSetSymbolicHotKeyEnabled(hotkey.rawValue, true)
    }
  }

  /// Install signal + uncaught-exception handlers once, at startup. We restore then
  /// re-raise with the default disposition, so a crash still produces its report and
  /// a `kill`/Ctrl-C still terminates — we just hand Cmd+Tab back on the way out.
  /// (We deliberately don't trap SIGSEGV/SIGBUS: doing Mach IPC from a handler when
  /// memory may be corrupt is riskier than the rare dead-key it would prevent.)
  static func installCrashGuards() {
    NSSetUncaughtExceptionHandler { _ in NativeHotkeyRestore.restoreAll() }
    for sig in [SIGTERM, SIGINT] {
      signal(sig) { received in
        NativeHotkeyRestore.restoreAll()
        signal(received, SIG_DFL)
        raise(received)
      }
    }
  }
}
