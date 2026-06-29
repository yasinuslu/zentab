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

  /// The window's center point (CoreGraphics global coords, top-left origin).
  var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

  /// Whether the window belongs to a monitor: its center lies within the monitor's
  /// frame. Both are CoreGraphics coords, so this composes with `CGDisplayBounds`.
  /// A nil frame means "any monitor" (no filtering).
  func isOnMonitor(_ monitorFrame: CGRect?) -> Bool {
    guard let monitorFrame else { return true }
    return monitorFrame.contains(center)
  }

  /// Windows smaller than this in either dimension are treated as chrome/helpers.
  static let minimumSize: CGFloat = 50

  /// AX subroles that are explicitly *not* user-switchable windows (palettes,
  /// floating tool windows, system dialogs). Everything else — including
  /// `AXStandardWindow`, `AXDialog`, an unknown subrole, or an empty one — is
  /// treated as a real window. A **denylist** (not an allowlist) so a real window
  /// that reports an odd subrole, like some Chrome/Electron windows, is never
  /// silently dropped. Reliability over precision.
  static let nonWindowSubroles: Set<String> = [
    "AXFloatingWindow", "AXSystemFloatingWindow", "AXSystemDialog",
  ]

  /// Pure predicate: is this a real, user-switchable window? Kept free of any AX
  /// call so it is exhaustively unit-testable from synthetic values.
  ///
  /// The current-app / other-apps modes show only on-screen windows, so minimized
  /// ones are excluded. The "everything" mode passes `includeMinimized: true` to
  /// surface them too; their AX frame is unreliable while minimized, so the size
  /// gate is skipped for them.
  static func isSwitchable(_ window: WindowInfo, includeMinimized: Bool = false) -> Bool {
    if window.isMinimized {
      guard includeMinimized else { return false }
    } else {
      guard window.frame.width >= minimumSize, window.frame.height >= minimumSize else {
        return false
      }
    }
    return !nonWindowSubroles.contains(window.subrole)
  }
}
