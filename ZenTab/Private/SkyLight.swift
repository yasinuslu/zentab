import ApplicationServices
import CoreGraphics

// Private SkyLight.framework (WindowServer / CGS + SkyLight Process Services)
// symbols, surfaced to Swift via @_silgen_name. There is NO Objective-C bridging
// header: each declaration below is an *unchecked* contract with the C ABI, so
// the argument widths, order, and return type must match the real symbol exactly
// (a mismatch compiles fine, then corrupts the stack at call time). Signatures
// were transcribed from the alt-tab-macos reference, which transcribed them from
// yabai / CGSInternal. SkyLight is linked via `-framework SkyLight` (see
// project.yml). These require App Sandbox OFF.
//
// Keep this file tiny and add symbols only as the feature that needs them lands.

/// A process's connection to the WindowServer. First argument to most CGS/SLS calls.
typealias CGSConnectionID = UInt32

/// Flags for `_SLPSSetFrontProcessWithOptions` (yabai's kCPS* constants).
enum SLPSMode: UInt32 {
  /// Bring all of the app's windows forward.
  case allWindows = 0x100
  /// Front-switch treated as user-initiated (not suppressed). What we use.
  case userGenerated = 0x200
  /// Front the process without raising any window.
  case noWindows = 0x400
}

/// Returns this process's WindowServer connection id. Cache it once.
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

/// Fronts the target *process* and brings a single window (`wid`) forward.
/// Does NOT make the window key — that needs a synthetic click (see WindowFocuser).
@_silgen_name("_SLPSSetFrontProcessWithOptions")
@discardableResult
func _SLPSSetFrontProcessWithOptions(
  _ psn: UnsafeMutablePointer<ProcessSerialNumber>,
  _ wid: CGWindowID,
  _ mode: UInt32
) -> CGError

/// Posts a raw CGSEventRecord byte buffer to the WindowServer for a process.
/// Used to synthesize the mouse-down/up pair that makes another app's window key.
@_silgen_name("SLPSPostEventRecordTo")
@discardableResult
func SLPSPostEventRecordTo(
  _ psn: UnsafeMutablePointer<ProcessSerialNumber>,
  _ bytes: UnsafeMutablePointer<UInt8>
) -> CGError

/// A WindowServer Space id.
typealias CGSSpaceID = UInt64
/// A display's UUID string (the "Display Identifier" from CGSCopyManagedDisplaySpaces).
typealias ScreenUuid = CFString

/// Which Spaces a window-query covers (yabai/CGS mask). `all` = 7.
enum CGSSpaceMask: Int {
  case current = 5
  case other = 6
  case all = 7
}

/// The current Space id on a given display.
@_silgen_name("CGSManagedDisplayGetCurrentSpace")
func CGSManagedDisplayGetCurrentSpace(_ cid: CGSConnectionID, _ displayUuid: ScreenUuid) -> CGSSpaceID

/// The Space ids a set of windows live on.
@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(
  _ cid: CGSConnectionID, _ mask: CGSSpaceMask.RawValue, _ windowIDs: CFArray
) -> CFArray

/// Sets the front process for ONE Space without touching the global front. Used to
/// repair the origin Space after a cross-Space focus (so returning there shows the
/// app that was there before, not the window we just raised — alt-tab #4507).
@_silgen_name("SLSSpaceSetFrontPSN")
@discardableResult
func SLSSpaceSetFrontPSN(
  _ cid: CGSConnectionID, _ sid: CGSSpaceID, _ psn: ProcessSerialNumber
) -> CGError

// MARK: - Window capture (cross-Space + minimized)

/// Flags for `CGSHWCaptureWindowList` (yabai/alt-tab constants).
struct CGSWindowCaptureOptions: OptionSet {
  let rawValue: UInt32
  /// Capture the full window bitmap ignoring its global clip/mask shape.
  static let ignoreGlobalClipShape = CGSWindowCaptureOptions(rawValue: 1 << 11)
  /// 1pt = 1px (1/4 the pixels of `bestResolution` on Retina).
  static let nominalResolution = CGSWindowCaptureOptions(rawValue: 1 << 9)
  /// Full backing-store resolution (Retina-native).
  static let bestResolution = CGSWindowCaptureOptions(rawValue: 1 << 8)
  /// Full-size regardless of Stage Manager skew.
  static let fullSize = CGSWindowCaptureOptions(rawValue: 1 << 19)
}

/// Hardware-path window capture. Returns a CFArray of `CGImage` for the given window
/// ids — and unlike ScreenCaptureKit's on-screen-only path, it captures **minimized
/// windows and windows on other Spaces** from their backing store. (It does NOT draw
/// offscreen content that was never rendered.) In practice it reliably returns the
/// image of the *first* id, so capture one window per call. Faster than the old
/// `CGWindowListCreateImage`. App Sandbox must be OFF.
@_silgen_name("CGSHWCaptureWindowList")
func CGSHWCaptureWindowList(
  _ cid: CGSConnectionID,
  _ windowList: UnsafeMutablePointer<CGWindowID>,
  _ windowCount: UInt32,
  _ options: CGSWindowCaptureOptions
) -> Unmanaged<CFArray>

/// The process-wide WindowServer connection, resolved once at first use.
let cgsConnection: CGSConnectionID = CGSMainConnectionID()

// MARK: - Native symbolic hotkeys (the Cmd+Tab override)

/// A native macOS "symbolic hotkey" — the system shortcuts the Dock/WindowServer
/// consume *before* any event tap sees them. To capture Cmd+Tab we must disable the
/// matching one(s); our `CGEventTap` then receives the keystroke like any other.
/// Raw values are the WindowServer's stable hotkey ids. `Int32` matches the C
/// `CGSSymbolicHotKey` (a plain `int`) the two SPIs below take.
enum SymbolicHotkey: Int32 {
  /// Cmd+Tab — switch to the next application.
  case commandTab = 1
  /// Cmd+Shift+Tab — the reverse switcher (must be disabled alongside `commandTab`).
  case commandShiftTab = 2
  /// Cmd+` (the key above Tab) — switch among the front app's windows.
  case commandKeyAboveTab = 6
}

/// Enable or disable a native symbolic hotkey. Disabling Cmd+Tab is what lets our
/// tap see it at all. NOTE: the effect **persists after this process exits**, so we
/// must restore (re-enable) on quit/crash or the user is left with a dead Cmd+Tab.
@_silgen_name("CGSSetSymbolicHotKeyEnabled")
@discardableResult
func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ isEnabled: Bool) -> CGError

/// Whether a native symbolic hotkey is currently enabled. The capture watchdog uses
/// this to verify Cmd+Tab is still ours — other apps, macOS updates, or a login can
/// silently re-enable it.
@_silgen_name("CGSIsSymbolicHotKeyEnabled")
func CGSIsSymbolicHotKeyEnabled(_ hotKey: Int32) -> Bool
