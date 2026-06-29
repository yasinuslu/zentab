import ApplicationServices

// SPI that physically lives inside the ALREADY-LINKED public frameworks
// (ApplicationServices / HIServices and Carbon), but is missing from the public
// headers. No extra link flag is needed for these two — only the @_silgen_name
// declaration. Same ABI-exactness caveat as SkyLight.swift applies.

/// Bridges an Accessibility window element to its CoreGraphics window id (the
/// `wid` fed to `_SLPSSetFrontProcessWithOptions` and the synthetic event).
/// Missing from the public AXUIElement headers.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(
  _ element: AXUIElement,
  _ wid: UnsafeMutablePointer<CGWindowID>
) -> AXError

/// Converts a pid to a Carbon ProcessSerialNumber. The SLPS front/key calls take
/// a PSN, not a pid, and there is no public replacement (still present through
/// macOS 15). The SDK *does* declare `GetProcessForPID` but marks it unavailable
/// to Swift, so we bind the same C symbol under a distinct Swift name to dodge the
/// collision.
@_silgen_name("GetProcessForPID")
@discardableResult
func zt_GetProcessForPID(
  _ pid: pid_t,
  _ psn: UnsafeMutablePointer<ProcessSerialNumber>
) -> OSStatus
