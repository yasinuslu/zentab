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

/// The process-wide WindowServer connection, resolved once at first use.
let cgsConnection: CGSConnectionID = CGSMainConnectionID()
