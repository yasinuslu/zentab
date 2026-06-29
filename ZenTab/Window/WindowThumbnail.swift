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
  /// SCK only sees on-screen windows, so ids on other Spaces won't be captured here
  /// (the cache + `hwCapture` cover those).
  static func capture(windowIDs: [CGWindowID], maxDimension: CGFloat = 480) async -> Captured {
    guard !windowIDs.isEmpty,
      let content = try? await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true)
    else { return Captured(images: [:]) }

    let wanted = Set(windowIDs)
    var images: [CGWindowID: CGImage] = [:]
    for window in content.windows where wanted.contains(window.windowID) {
      if let image = await snapshot(window, maxDimension: maxDimension) {
        images[window.windowID] = image
      }
    }
    return Captured(images: images)
  }

  /// Capture every on-screen, normal-level window (capped), to keep the cache fresh
  /// in the background. On-screen only on purpose: a window on another Space isn't
  /// being composited, so its look can't change while it's away — its last on-screen
  /// frame stays valid until it returns.
  static func captureOnScreen(limit: Int = 16, maxDimension: CGFloat = 480) async -> Captured {
    guard
      let content = try? await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true)
    else { return Captured(images: [:]) }

    let windows = content.windows
      .filter { $0.windowLayer == 0 && $0.frame.width >= 50 && $0.frame.height >= 50 }
      .prefix(limit)
    var images: [CGWindowID: CGImage] = [:]
    for window in windows {
      if let image = await snapshot(window, maxDimension: maxDimension) {
        images[window.windowID] = image
      }
    }
    return Captured(images: images)
  }

  private static func snapshot(_ window: SCWindow, maxDimension: CGFloat) async -> CGImage? {
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let configuration = SCStreamConfiguration()
    let longestSide = max(window.frame.width, window.frame.height, 1)
    let scale = min(1.0, maxDimension / longestSide)
    configuration.width = max(1, Int(window.frame.width * scale))
    configuration.height = max(1, Int(window.frame.height * scale))
    configuration.showsCursor = false
    return try? await SCScreenshotManager.captureImage(
      contentFilter: filter, configuration: configuration)
  }

  // MARK: - Private hardware capture (cross-Space + minimized)

  /// Capture one window via the private WindowServer path, which works for windows
  /// on other Spaces and minimized windows (what SCK can't reach). Synchronous; call
  /// it off the main thread. Returns nil if the WindowServer hands back nothing.
  static func hwCapture(_ windowID: CGWindowID) -> CGImage? {
    var wid = windowID
    let options: CGSWindowCaptureOptions = [.ignoreGlobalClipShape, .bestResolution, .fullSize]
    let array =
      CGSHWCaptureWindowList(cgsConnection, &wid, 1, options).takeRetainedValue() as? [CGImage]
    return array?.first
  }

  /// Smoke-test `hwCapture` across a set of ids without touching the hot path: how
  /// many returned an image, plus a sample size. Runs off-main (the calls are sync).
  static func hwCaptureSummary(for ids: [CGWindowID]) async -> String {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        var captured = 0
        var sample = ""
        for id in ids {
          guard let image = hwCapture(id) else { continue }
          captured += 1
          if sample.isEmpty { sample = "\(image.width)×\(image.height)" }
        }
        continuation.resume(
          returning: "HW capture: \(captured)/\(ids.count) windows"
            + (sample.isEmpty ? "" : " · sample \(sample)"))
      }
    }
  }
}

/// A bounded, most-recently-used cache of each window's last successful thumbnail,
/// so the overlay can paint a window's latest known frame instantly on summon and
/// fall back to it when a live capture is unavailable — notably when the window is
/// on another Space or monitor, which ScreenCaptureKit will not capture live. The
/// fallback chain the grid realizes is: **live capture > cached last-known > icon**.
///
/// Main-actor isolated: read and written only from `OverlayController`, so it needs
/// no locking. CGImage is immutable, so retaining one is safe.
@MainActor
final class ThumbnailCache {
  private var store: [CGWindowID: CGImage] = [:]
  private var order: [CGWindowID] = []  // least-recently-used first
  private let limit: Int

  init(limit: Int = 128) { self.limit = limit }

  /// Cached frames for `ids`, ready to hand to `TileGridView.applyThumbnails`.
  /// Reading a frame marks it recently used so it survives eviction while on screen.
  func frames(for ids: [CGWindowID]) -> [CGWindowID: CGImage] {
    var result: [CGWindowID: CGImage] = [:]
    for id in ids where store[id] != nil {
      result[id] = store[id]
      touch(id)
    }
    return result
  }

  /// Remember each freshly captured frame as that window's latest known state.
  func remember(_ images: [CGWindowID: CGImage]) {
    for (id, image) in images {
      store[id] = image
      touch(id)
    }
    evict()
  }

  private func touch(_ id: CGWindowID) {
    if let index = order.firstIndex(of: id) { order.remove(at: index) }
    order.append(id)
  }

  private func evict() {
    while order.count > limit { store[order.removeFirst()] = nil }
  }
}
