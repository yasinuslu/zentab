import AppKit

/// A dev-only, headless renderer that lays out the `TileGridView` and draws its CALayers to a
/// sharp PNG **offscreen** — no Screen Recording permission, no GUI, no `screencapture` (which
/// the system privacy-blurs for unentitled callers). It isolates the frosted card so the
/// design can be checked pixel-for-pixel against the website. The backdrop blur is environmental
/// and not part of this view, so we paint a representative desktop gradient + dim underneath to
/// mimic the receded world the card floats over.
///
/// Driven from `ZenTabMain` via `--render-overlay <path> [--board]`; renders and exits.
enum OverlayRenderer {
  static func run(path: String, board: Bool) -> Never {
    _ = NSApplication.shared  // bring up the AppKit environment for text/layer drawing
    autoreleasepool {
      let size = CGSize(width: 1500, height: 950)
      let view = TileGridView(frame: CGRect(origin: .zero, size: size))

      let apps = NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular && $0.icon != nil }
      let sample = apps.prefix(11).enumerated().map { offset, app -> WindowInfo in
        WindowInfo(
          pid: app.processIdentifier, windowID: CGWindowID(90000 + offset),
          title: app.localizedName ?? "Window", appName: app.localizedName ?? "App",
          frame: .zero, isMinimized: offset % 5 == 4, isFullscreen: false,
          subrole: "AXStandardWindow")
      }
      guard !sample.isEmpty else { exit(1) }
      let hereStart = board ? max(1, sample.count - 3) : 0
      let header = TileGridView.Header(
        key: board ? "⌥ Tab" : "⌘ Tab",
        label: board ? "Everything, everywhere" : "All windows · this display")
      view.configure(
        windows: Array(sample), hereStart: hereStart, selectedIndex: board ? 0 : 1, header: header)

      let scale: CGFloat = 2
      guard
        let ctx = CGContext(
          data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { exit(1) }
      ctx.scaleBy(x: scale, y: scale)
      drawBackground(in: ctx, size: size)
      view.layer?.render(in: ctx)

      guard let image = ctx.makeImage(),
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
      else { exit(1) }
      do {
        try data.write(to: URL(fileURLWithPath: path))
      } catch {
        FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
        exit(1)
      }
      FileHandle.standardError.write(Data("rendered \(path)\n".utf8))
    }
    exit(0)
  }

  /// A representative desktop behind the card: the website demo's blue radial fading to near
  /// black, then the backdrop dim. (No blur — this is for verifying the card, not the scrim.)
  private static func drawBackground(in ctx: CGContext, size: CGSize) {
    let colors =
      [
        NSColor(srgbRed: 0x1F / 255, green: 0x35 / 255, blue: 0x50 / 255, alpha: 1).cgColor,
        NSColor(srgbRed: 0x14 / 255, green: 0x20 / 255, blue: 0x2F / 255, alpha: 1).cgColor,
        NSColor(srgbRed: 0x0C / 255, green: 0x11 / 255, blue: 0x19 / 255, alpha: 1).cgColor,
      ] as CFArray
    if let gradient = CGGradient(
      colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.4, 0.85])
    {
      let center = CGPoint(x: size.width * 0.35, y: size.height * 0.9)
      ctx.drawRadialGradient(
        gradient, startCenter: center, startRadius: 0, endCenter: center,
        endRadius: size.width * 0.95, options: [.drawsAfterEndLocation])
    }
    // The backdrop dim (slightly lighter than the live 0.55 to stand in for the blur's lift).
    ctx.setFillColor(NSColor(srgbRed: 6 / 255, green: 7 / 255, blue: 10 / 255, alpha: 0.45).cgColor)
    ctx.fill(CGRect(origin: .zero, size: size))
  }
}
