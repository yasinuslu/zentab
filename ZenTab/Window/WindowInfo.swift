import CoreGraphics
import Foundation

/// A single switchable window, captured as a plain, `Sendable` value so it can be
/// produced off the main thread (by the Accessibility/CGS enumerator) and handed
/// to the `@MainActor` overlay without any actor-isolation gymnastics. It holds
/// no AX/CGS handles on purpose: all live lookups happen at enumeration time.
struct WindowInfo: Sendable, Identifiable, Equatable {
  /// The owning application's process id.
  let pid: pid_t
  /// CoreGraphics window id (from `_AXUIElementGetWindow`); the focus/capture key.
  let windowID: CGWindowID
  /// Window title, may be empty (some apps withhold it without Screen Recording).
  let title: String
  /// Localized application name, for the tile label / fallback when title is empty.
  let appName: String
  /// Window frame in screen coordinates (top-left origin, AX convention).
  let frame: CGRect
  /// Whether the window is currently minimized to the Dock.
  let isMinimized: Bool
  /// AX subrole, e.g. "AXStandardWindow" or "AXDialog".
  let subrole: String

  var id: CGWindowID { windowID }

  /// Windows smaller than this in either dimension are treated as chrome/helpers.
  static let minimumSize: CGFloat = 50

  /// Pure predicate: is this a real, user-switchable window? Kept free of any AX
  /// call so it is exhaustively unit-testable from synthetic values.
  ///
  /// For the MVP "other apps" mode we only show on-screen, current-Space windows,
  /// so minimized windows are excluded (the public capture path can't image them
  /// anyway). The cross-Space "everything" mode will relax this later.
  static func isSwitchable(_ window: WindowInfo) -> Bool {
    guard !window.isMinimized else { return false }
    guard window.frame.width >= minimumSize, window.frame.height >= minimumSize else {
      return false
    }
    switch window.subrole {
    case "AXStandardWindow", "AXDialog": return true
    default: return false
    }
  }
}
