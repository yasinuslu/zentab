import CoreGraphics
import ScreenCaptureKit

/// Window capture via ScreenCaptureKit, the supported macOS 14+ path
/// (`CGWindowListCreateImage` is obsoleted at our deployment target). Requires
/// Screen Recording; without it capture returns empty and tiles fall back to
/// app icon + title, so the switcher still works before that permission is granted.
enum WindowThumbnail {
  /// CGImage is not `Sendable`; wrap the result so it can cross back to the
  /// main actor without a strict-concurrency complaint.
  struct Captured: @unchecked Sendable {
    let images: [CGWindowID: CGImage]
  }

  /// Capture thumbnails for the given window ids in one ShareableContent pass.
  static func capture(windowIDs: [CGWindowID], maxDimension: CGFloat = 480) async -> Captured {
    guard !windowIDs.isEmpty,
      let content = try? await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true)
    else { return Captured(images: [:]) }

    let wanted = Set(windowIDs)
    var images: [CGWindowID: CGImage] = [:]
    for window in content.windows where wanted.contains(window.windowID) {
      let filter = SCContentFilter(desktopIndependentWindow: window)
      let configuration = SCStreamConfiguration()
      let longestSide = max(window.frame.width, window.frame.height, 1)
      let scale = min(1.0, maxDimension / longestSide)
      configuration.width = max(1, Int(window.frame.width * scale))
      configuration.height = max(1, Int(window.frame.height * scale))
      configuration.showsCursor = false
      let image = try? await SCScreenshotManager.captureImage(
        contentFilter: filter, configuration: configuration)
      if let image { images[window.windowID] = image }
    }
    return Captured(images: images)
  }
}
