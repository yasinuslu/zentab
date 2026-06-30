// ZenTab branding artwork — the single source of truth for the app icon and the
// installer DMG visuals, expressed as code so they regenerate exactly and stay
// pinned to the brand.
//
// The mark is transcribed from the canonical brand page
// (website/src/pages/Brand.tsx, the "app icon" lockup): a dark rounded-square
// body, an outlined frame (the switcher — steady, always there) and a single
// electric tile offset into the corner (the one window in focus). Colors are the
// website brand palette; #5D6DFF "Electric" is the one accent.
//
// Run via `bin/branding` (which assembles the .appiconset, the volume .icns and
// the retina DMG background from what this writes). Drawing is resolution
// independent — every size is rendered fresh, never upscaled — so small sizes
// stay crisp.
//
//   swift GenerateBranding.swift <out-dir>
//
// Output:
//   <out-dir>/ZenTab.iconset/icon_*.png   (Apple-named; feeds iconutil + the asset catalog)
//   <out-dir>/dmg/background.png, background@2x.png

import AppKit
import CoreGraphics

// MARK: - Brand palette (website/src/pages/Brand.tsx)

func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
  CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let bodyTop = c(26, 29, 40)  // #1a1d28  icon body gradient, top
let bodyBot = c(13, 14, 19)  // #0d0e13  icon body gradient, bottom
let accentHi = c(114, 130, 255)  // #7282ff  tile gradient, light
let accentLo = c(81, 96, 255)  // #5160ff  tile gradient, deep
let voidTop = c(20, 22, 31)  // #14161f  dmg backdrop, top
let voidBot = c(11, 12, 15)  // #0B0C0F  dmg backdrop / "Void"
let accent = c(93, 109, 255)  // #5D6DFF  Electric — the one accent
let white = { (a: Double) in c(255, 255, 255, a) }

// MARK: - Drawing primitives

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext(_ w: Int, _ h: Int) -> CGContext {
  let ctx = CGContext(
    data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
    space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.setAllowsAntialiasing(true)
  ctx.interpolationQuality = .high
  return ctx
}

func roundRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
  CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func linearGradient(_ ctx: CGContext, _ rect: CGRect, _ from: CGColor, _ to: CGColor) {
  let grad = CGGradient(colorsSpace: srgb, colors: [from, to] as CFArray, locations: [0, 1])!
  // Top-left → bottom-right diagonal (matches the brand's ~150–160° gradients).
  ctx.drawLinearGradient(
    grad,
    start: CGPoint(x: rect.minX, y: rect.maxY),
    end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
}

func writePNG(_ ctx: CGContext, to url: URL) {
  let img = ctx.makeImage()!
  let rep = NSBitmapImageRep(cgImage: img)
  rep.size = NSSize(width: img.width, height: img.height)  // honor true pixel size
  let data = rep.representation(using: .png, properties: [:])!
  try! data.write(to: url)
}

// MARK: - App icon

func drawIcon(_ ctx: CGContext, _ n: CGFloat) {
  // macOS app-icon grid: the body sits inset ~100/1024 inside a transparent
  // canvas, a superellipse-ish rounded square at ~22.5% corner radius, with a
  // soft drop shadow below.
  let inset = n * 100.0 / 1024.0
  let body = CGRect(x: inset, y: inset, width: n - 2 * inset, height: n - 2 * inset)
  let bodyRadius = body.width * 0.2255

  // Drop shadow cast by the body.
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -n * 0.012), blur: n * 0.05, color: c(0, 0, 0, 0.55))
  ctx.addPath(roundRect(body, bodyRadius))
  ctx.setFillColor(bodyBot)
  ctx.fillPath()
  ctx.restoreGState()

  // Body gradient + a faint top sheen.
  ctx.saveGState()
  ctx.addPath(roundRect(body, bodyRadius))
  ctx.clip()
  linearGradient(ctx, body, bodyTop, bodyBot)
  let sheen = CGGradient(
    colorsSpace: srgb, colors: [white(0.06), white(0)] as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(
    sheen, start: CGPoint(x: body.midX, y: body.maxY),
    end: CGPoint(x: body.midX, y: body.midY), options: [])
  ctx.restoreGState()

  // Hairline rim.
  ctx.saveGState()
  let bw = max(1, n * 0.0018)
  ctx.addPath(roundRect(body.insetBy(dx: bw / 2, dy: bw / 2), bodyRadius - bw / 2))
  ctx.setStrokeColor(white(0.14))
  ctx.setLineWidth(bw)
  ctx.strokePath()
  ctx.restoreGState()

  // The mark, centered. Ratios transcribed from the brand "app icon" lockup
  // (48px mark inside an 88px tile; frame 2px / r13, tile 33px at offset 15 / r10).
  let mark = body.width * 0.54
  let mx = body.midX - mark / 2
  let my = body.midY - mark / 2
  let markRect = CGRect(x: mx, y: my, width: mark, height: mark)

  // Frame: an outlined rounded square — the switcher, steady and always there.
  ctx.saveGState()
  let fw = mark * 0.05
  let frameRadius = mark * 0.27
  ctx.addPath(roundRect(markRect.insetBy(dx: fw / 2, dy: fw / 2), frameRadius - fw / 2))
  ctx.setStrokeColor(white(0.32))
  ctx.setLineWidth(fw)
  ctx.strokePath()
  ctx.restoreGState()

  // Tile: a filled electric square flush to the frame's bottom-right corner —
  // the one window in focus. Glow first, then the gradient face on top.
  let tile = mark * 0.6875
  let tileRect = CGRect(x: mx + mark * 0.3125, y: my, width: tile, height: tile)
  let tileRadius = mark * 0.208

  ctx.saveGState()
  ctx.setShadow(
    offset: CGSize(width: 0, height: -tile * 0.10), blur: tile * 0.30, color: c(93, 109, 255, 0.6))
  ctx.addPath(roundRect(tileRect, tileRadius))
  ctx.setFillColor(accentLo)
  ctx.fillPath()
  ctx.restoreGState()

  ctx.saveGState()
  ctx.addPath(roundRect(tileRect, tileRadius))
  ctx.clip()
  linearGradient(ctx, tileRect, accentHi, accentLo)
  ctx.restoreGState()
}

// MARK: - DMG background

func drawText(
  _ ctx: CGContext, _ s: String, center: CGPoint, size: CGFloat, color: NSColor, mono: Bool,
  kern: CGFloat
) {
  let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = nsctx
  let font =
    mono
    ? NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    : NSFont.systemFont(ofSize: size, weight: .medium)
  let str = NSAttributedString(
    string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern])
  let sz = str.size()
  str.draw(at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2))
  NSGraphicsContext.restoreGraphicsState()
}

// Designed for a 660×400 install window; @2x doubles every value via `scale`.
func drawBackground(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
  let scale = w / 660.0

  // Void backdrop with a single soft accent glow up top — the brand's calm scrim.
  ctx.saveGState()
  ctx.addRect(CGRect(x: 0, y: 0, width: w, height: h))
  ctx.clip()
  linearGradient(ctx, CGRect(x: 0, y: 0, width: w, height: h), voidTop, voidBot)
  let glow = CGGradient(
    colorsSpace: srgb, colors: [c(93, 109, 255, 0.16), c(93, 109, 255, 0)] as CFArray,
    locations: [0, 1])!
  ctx.drawRadialGradient(
    glow, startCenter: CGPoint(x: w * 0.5, y: h * 0.95), startRadius: 0,
    endCenter: CGPoint(x: w * 0.5, y: h * 0.95), endRadius: w * 0.45, options: [])
  ctx.restoreGState()

  // The two drop targets live at Finder y=170 (from the top). Convert to the
  // bottom-left context and draw a quiet arrow between them.
  let yC = h * (1 - 170.0 / 400.0)
  let ax0 = 250.0 * scale, ax1 = 410.0 * scale
  let head = 13.0 * scale
  ctx.saveGState()
  ctx.setStrokeColor(c(93, 109, 255, 0.6))
  ctx.setLineWidth(3 * scale)
  ctx.setLineCap(.round)
  ctx.setLineJoin(.round)
  ctx.move(to: CGPoint(x: ax0, y: yC))
  ctx.addLine(to: CGPoint(x: ax1, y: yC))
  ctx.strokePath()
  ctx.move(to: CGPoint(x: ax1 - head, y: yC + head))
  ctx.addLine(to: CGPoint(x: ax1, y: yC))
  ctx.addLine(to: CGPoint(x: ax1 - head, y: yC - head))
  ctx.strokePath()
  ctx.restoreGState()

  // A single, plain instruction. No pitch — just what to do.
  drawText(
    ctx, "Drag ZenTab into Applications",
    center: CGPoint(x: w * 0.5, y: h * (1 - 320.0 / 400.0)),
    size: 15 * scale, color: NSColor(srgbRed: 155 / 255, green: 158 / 255, blue: 169 / 255, alpha: 1),
    mono: false, kern: 0.2 * scale)
}

// MARK: - Main

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./branding-out"
let fm = FileManager.default
let outURL = URL(fileURLWithPath: out, isDirectory: true)

let iconsetURL = outURL.appendingPathComponent("ZenTab.iconset")
try? fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

// Apple iconset names → pixel size. These exact names feed both `iconutil`
// and the asset catalog (16@2x == 32, etc.).
let iconEntries: [(String, Int)] = [
  ("icon_16x16", 16), ("icon_16x16@2x", 32),
  ("icon_32x32", 32), ("icon_32x32@2x", 64),
  ("icon_128x128", 128), ("icon_128x128@2x", 256),
  ("icon_256x256", 256), ("icon_256x256@2x", 512),
  ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in iconEntries {
  let ctx = makeContext(px, px)
  drawIcon(ctx, CGFloat(px))
  writePNG(ctx, to: iconsetURL.appendingPathComponent("\(name).png"))
}

let dmgURL = outURL.appendingPathComponent("dmg")
try? fm.createDirectory(at: dmgURL, withIntermediateDirectories: true)
for (name, mult) in [("background", 1), ("background@2x", 2)] {
  let w = 660 * mult, h = 400 * mult
  let ctx = makeContext(w, h)
  drawBackground(ctx, CGFloat(w), CGFloat(h))
  writePNG(ctx, to: dmgURL.appendingPathComponent("\(name).png"))
}

print("ZenTab branding artwork written to \(outURL.path)")
