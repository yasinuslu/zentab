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

// MARK: - Move a window to a Space (window curation: summon / fling)

/// Move the given windows (a CFArray of CGWindowID numbers) to one managed Space. This
/// is the single call the curation feature rests on: aim it at the *current* Space to
/// "bring here" (summon), or an adjacent Space to "send away" (fling). Does NOT move
/// native-fullscreen windows. Whether it works on **another app's** window without SIP
/// on this macOS is exactly what the menu/`SIGUSR2` spike verifies before any UI is built.
@_silgen_name("CGSMoveWindowsToManagedSpace")
func CGSMoveWindowsToManagedSpace(_ cid: CGSConnectionID, _ windowIDs: CFArray, _ space: CGSSpaceID)

/// Add the given windows to the given Spaces (without removing them from their current
/// ones). The spike's fallback move path: `CGSAddWindowsToSpaces` to the destination,
/// then `CGSRemoveWindowsFromSpaces` from the origin, in case the single move no-ops.
@_silgen_name("CGSAddWindowsToSpaces")
func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windowIDs: CFArray, _ spaceIDs: CFArray)

/// Remove the given windows from the given Spaces. Paired with `CGSAddWindowsToSpaces`
/// to emulate a move (add to destination, remove from origin).
@_silgen_name("CGSRemoveWindowsFromSpaces")
func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windowIDs: CFArray, _ spaceIDs: CFArray)

// MARK: - Space enumeration + extra move strategies (cross-Space move spike)

/// The full managed-Space layout: a CFArray of per-display NSDictionaries. Each has a
/// `"Display Identifier"` (a `ScreenUuid`, or the literal `"Main"`), a `"Current Space"`
/// dict, and a `"Spaces"` array of dicts each carrying an `"id64"` (`CGSSpaceID`). The
/// spike uses it to enumerate the Spaces on a display and pick a destination `S2 != S1`.
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

/// Switch a display's *current* (visible) Space to `sid`. The spike uses this only for
/// the "switch to dest, move, switch back" degraded strategy; the shipped curation
/// feature must never force a Space switch. `display` is the display UUID string.
@_silgen_name("CGSManagedDisplaySetCurrentSpace")
func CGSManagedDisplaySetCurrentSpace(_ cid: CGSConnectionID, _ display: CFString, _ sid: CGSSpaceID)

/// alt-tab experimental (annotated working only 10.10–12.2): add windows to `sid` and
/// remove them from the other Spaces in one call. `selector` is the undocumented mask
/// (yabai/alt-tab pass `0x80007`). Tried on macOS 26 as a ladder fallback.
@_silgen_name("CGSSpaceAddWindowsAndRemoveFromSpaces")
func CGSSpaceAddWindowsAndRemoveFromSpaces(
  _ cid: CGSConnectionID, _ sid: CGSSpaceID, _ windowIDs: CFArray, _ selector: Int)

/// alt-tab experimental: move a window list to Space `sid`. `windowCount` is the count
/// of ids in `windowList`. Returns an `OSStatus`. Tried on macOS 26 as a ladder fallback.
@_silgen_name("CGSMoveWorkspaceWindowList")
@discardableResult
func CGSMoveWorkspaceWindowList(
  _ cid: CGSConnectionID, _ windowList: CFArray, _ windowCount: UInt, _ sid: CGSSpaceID
) -> OSStatus

// MARK: - yabai's no-SIP move paths (the ones it actually uses on macOS ≥15)

/// The `SLS`-prefixed twin of `CGSMoveWindowsToManagedSpace`. SkyLight exports both; yabai
/// calls the `SLS` form. (yabai *skips* this on macOS ≥15 — `workspace_use_macos_space_workaround`
/// is true there — but we try it to confirm whether the plain call is truly inert on 26.)
@_silgen_name("SLSMoveWindowsToManagedSpace")
func SLSMoveWindowsToManagedSpace(_ cid: CGSConnectionID, _ windowIDs: CFArray, _ space: CGSSpaceID)

/// Give a Space a temporary "compat id" (a workspace tag). Paired with
/// `SLSSetWindowListWorkspace`, this is yabai's no-scripting-addition move fallback:
/// tag the destination Space, set the window's workspace to that tag (which relocates it),
/// then clear the tag. `workspace` is a 32-bit tag (yabai uses `0x79616265` = "yabe").
@_silgen_name("SLSSpaceSetCompatID")
@discardableResult
func SLSSpaceSetCompatID(_ cid: CGSConnectionID, _ sid: CGSSpaceID, _ workspace: Int32) -> CGError

/// Set the workspace tag of a window list (a C array of CGWindowID + count). With a Space
/// temporarily carrying the matching compat id, this lands the windows on that Space — the
/// no-SIP "compat id dance" from yabai's `space_manager_move_window_to_space`.
@_silgen_name("SLSSetWindowListWorkspace")
@discardableResult
func SLSSetWindowListWorkspace(
  _ cid: CGSConnectionID, _ windowList: UnsafeMutablePointer<CGWindowID>, _ windowCount: Int32,
  _ workspace: Int32
) -> CGError

/// Assign an entire *process* (all its windows) to one Space. yabai uses this directly
/// from a normal connection (no scripting addition) in `space_manager_assign_process_to_space`.
@_silgen_name("SLSProcessAssignToSpace")
@discardableResult
func SLSProcessAssignToSpace(_ cid: CGSConnectionID, _ pid: pid_t, _ sid: CGSSpaceID) -> CGError

/// Assign an entire *process* to all Spaces (sticky). Pair with `SLSProcessAssignToSpace`
/// to "unstick" onto a single Space.
@_silgen_name("SLSProcessAssignToAllSpaces")
@discardableResult
func SLSProcessAssignToAllSpaces(_ cid: CGSConnectionID, _ pid: pid_t) -> CGError

/// The window ids the WindowServer composites on the given Space(s) — the *authoritative*
/// per-Space membership Mission Control itself renders (works for non-current Spaces too).
/// yabai calls it with `owner = 0` (any), `options = 0x7` (incl. minimized), zeroed tags.
/// We use it to confirm a cross-Space move is real (window enters the destination Space's
/// list and leaves the origin's), not just a bookkeeping/"sticky" side effect.
@_silgen_name("SLSCopyWindowsWithOptionsAndTags")
func SLSCopyWindowsWithOptionsAndTags(
  _ cid: CGSConnectionID, _ owner: UInt32, _ spaces: CFArray, _ options: UInt32,
  _ setTags: UnsafeMutablePointer<UInt64>, _ clearTags: UnsafeMutablePointer<UInt64>
) -> Unmanaged<CFArray>?

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
