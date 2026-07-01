import AppKit

/// Every color, radius, and metric the overlay draws, in one place — a faithful
/// transcription of the **website overlay design** (`website/src/pages/Overlay.tsx` and the
/// brand tokens in `website/src/theme.css`). The website is the canonical visual spec for
/// both native apps; change a value there first, then mirror it here.
///
/// ZenTab's overlay is a **forced-dark "spotlight"** regardless of the OS light/dark theme —
/// the panels pin their appearance to `.darkAqua` and we paint our own colors on top of a
/// dimmed, blurred backdrop. That is deliberate: a switcher is a moment where "the rest of
/// the world recedes" (VISION), and a single dark treatment both reads that way and sidesteps
/// the light-mode contrast problems a theme-adaptive overlay invites.
enum OverlayTheme {
  /// Pinned on every overlay panel so the look never depends on the system theme.
  /// Computed (not stored) so it stays concurrency-safe — `NSAppearance` isn't `Sendable`.
  static var appearance: NSAppearance? { NSAppearance(named: .darkAqua) }

  /// The ZenTab signature accent — website `--accent` **#5D6DFF** ("Electric"), the one
  /// brand color shared by both native apps. Used like a single held note: it marks the one
  /// window in focus and nothing else.
  static let accent = NSColor(srgbRed: 0x5D / 255, green: 0x6D / 255, blue: 0xFF / 255, alpha: 1)

  /// Soft fade for the backdrop and the content card — calm, not slow (VISION: ~80–120 ms).
  static let fadeDuration: CFTimeInterval = 0.12

  /// The overlay's appear animation (website `ovIn`: scale .97 → 1, fade in), on the snappy
  /// ease the design uses everywhere. `summonEase` is computed (a fresh instance per read) so
  /// it stays concurrency-safe — `CAMediaTimingFunction` isn't `Sendable`.
  static let summonScaleFrom: CGFloat = 0.97
  static var summonEase: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.22, 0.61, 0.36, 1) }

  // MARK: Responsive up-scaling (big external displays)

  /// The base metrics below are tuned for a laptop-class display; the reference is the 16"
  /// MacBook's ~1728×1117 pt logical size, where the overlay "feels right" today. On a larger
  /// monitor the whole card — tiles, thumbnails, icons, text, chips — is multiplied by this
  /// factor so a switch stays big and legible at a glance instead of shrinking into the middle
  /// of the screen. We take the *smaller* of the width and height ratios so a short or ultrawide
  /// display (e.g. 3440×1080) doesn't up-scale into a card that overflows vertically. Clamped so
  /// every laptop is unchanged (floor 1.0) and huge displays don't balloon (ceiling 1.5). Driven
  /// off the panel's own bounds, which the controller sizes to the active screen, so the renderer
  /// and the live app agree.
  static func tileScale(forSize size: CGSize) -> CGFloat {
    let referenceWidth: CGFloat = 1728
    let referenceHeight: CGFloat = 1117
    guard size.width > 0, size.height > 0 else { return 1 }
    let fit = min(size.width / referenceWidth, size.height / referenceHeight)
    return min(1.5, max(1.0, fit))
  }

  // MARK: Backdrop (the world recedes)

  enum Backdrop {
    /// A dark, GPU-composited blur behind everything; the dim layer rides on top of it.
    static let material: NSVisualEffectView.Material = .fullScreenUI
    /// The website scrim is a flat `rgba(6,7,10,.55)`, but its *look* — a cool, atmospheric
    /// near-black that lifts slightly toward the top-left — comes from the dark desktop showing
    /// through it. A real Mac has no such designed desktop: the user's wallpaper might be bright,
    /// and a flat 0.55 dim then reads as a washed-out gray, nothing like the website.
    ///
    /// So we bake the website's *composite* backdrop (its desktop gradient seen through the
    /// scrim) straight into the dim as a radial gradient, and drive it nearly opaque. The
    /// spotlight then recedes to the same dark regardless of wallpaper — only a sliver of the
    /// blurred world bleeds through for life (VISION: the world recedes but stays legible).
    /// `dimInner` is the lifted top-left tone (≈ website `#1f3550` under the scrim); `dimOuter`
    /// is the near-black the corners sink to (≈ website `#0c1119` under the scrim).
    static let dimInner = NSColor(srgbRed: 0x12 / 255, green: 0x1C / 255, blue: 0x29 / 255, alpha: 0.82)
    static let dimOuter = NSColor(srgbRed: 0x06 / 255, green: 0x07 / 255, blue: 0x0A / 255, alpha: 0.86)
    /// Radial-gradient geometry, in the panel's unit space (origin bottom-left, y up). The bright
    /// origin sits high and to the left like the website; the end point pushes the dark tone past
    /// the far corner so it fills the whole scrim.
    static let dimCenter = CGPoint(x: 0.32, y: 0.82)
    static let dimEdge = CGPoint(x: 1.15, y: -0.15)
  }

  // MARK: The frosted content card (one panel holds everything)

  enum Card {
    static let radius: CGFloat = 24
    static let padding: CGFloat = 22
    /// Website panel `rgba(24,26,33,.72)` over the blurred backdrop = a frosted dark sheet.
    static let fill = NSColor(srgbRed: 24 / 255, green: 26 / 255, blue: 33 / 255, alpha: 0.72)
    static let border = NSColor.white.withAlphaComponent(0.12)
    static let borderWidth: CGFloat = 1
    static let shadowColor = NSColor.black.withAlphaComponent(0.6)
    static let shadowRadius: CGFloat = 60  // website blur 120 / 2
    static let shadowOffset = CGSize(width: 0, height: -24)
    /// The hairline dividers (header→content is implicit spacing; this is the zone divider
    /// and the footer rule). Website `rgba(255,255,255,.07–.08)`.
    static let divider = NSColor.white.withAlphaComponent(0.08)
    /// Minimum inner width so the header/footer hint rows never wrap and the card stays the
    /// website's generous, fixed-feeling width even with only a couple of windows.
    static let minContentWidth: CGFloat = 820
  }

  // MARK: Header (key pill · mode label · count)

  enum Header {
    static let height: CGFloat = 28
    static let bottomGap: CGFloat = 18
    static let labelColor = NSColor(srgbRed: 0xEC / 255, green: 0xED / 255, blue: 0xF1 / 255, alpha: 1)
    static let labelSize: CGFloat = 15
    static let countColor = NSColor(srgbRed: 0x5E / 255, green: 0x61 / 255, blue: 0x6C / 255, alpha: 1)
    static let countSize: CGFloat = 11
    static let gap: CGFloat = 12  // between the pill and the label

    // The key pill: accent text in an accent-outlined chip.
    static let pillText = accent
    static let pillBorder = accent.withAlphaComponent(0.35)
    static let pillFill = accent.withAlphaComponent(0.0)
    static let pillSize: CGFloat = 12
    static let pillRadius: CGFloat = 7
    static let pillHPad: CGFloat = 9
  }

  // MARK: Zone heads (ELSEWHERE / THIS SPACE)

  enum Zone {
    static let headColor = NSColor(srgbRed: 0x62 / 255, green: 0x64 / 255, blue: 0x6E / 255, alpha: 1)
    static let hintColor = accent
    static let headSize: CGFloat = 10
    static let headKern: CGFloat = 2  // ≈ 0.2em tracking at 10px (website letter-spacing)
    static let headHeight: CGFloat = 14
    static let headBottomGap: CGFloat = 12
    /// Space between the ELSEWHERE block and the divider that opens the THIS SPACE block.
    static let gap: CGFloat = 20
    static let dividerTopGap: CGFloat = 18
    /// One-line placeholder height when nothing is in THIS SPACE yet.
    static let emptyHintHeight: CGFloat = 20
  }

  // MARK: Footer hint row

  enum Footer {
    static let topGap: CGFloat = 16
    static let height: CGFloat = 14
    static let size: CGFloat = 11
    static let keyColor = NSColor(srgbRed: 0x9B / 255, green: 0x9E / 255, blue: 0xA9 / 255, alpha: 1)
    static let textColor = NSColor(srgbRed: 0x5E / 255, green: 0x61 / 255, blue: 0x6C / 255, alpha: 1)
    static let accentColor = accent
  }

  // MARK: Tiles

  enum Tile {
    /// Uniform across both zones (website renders the same tile everywhere). Height carries the
    /// taller footer that holds the enlarged app icon; the thumbnail area is unchanged.
    static let size = CGSize(width: 200, height: 166)
    static let radius: CGFloat = 15
    /// Inset of the content (thumbnail/footer) from the tile edge — website padding 5.
    static let pad: CGFloat = 5
    static let borderWidth: CGFloat = 2
    /// Taller than before so the app icon — the fastest "which window is this" cue — can be
    /// large without crowding the title.
    static let footerHeight: CGFloat = 40
    /// The app icon is the primary glance identifier, so it's deliberately prominent (was 18).
    static let iconSize: CGFloat = 28
    static let titleSize: CGFloat = 13

    static let fill = NSColor.white.withAlphaComponent(0.02)
    static let selectedFill = accent.withAlphaComponent(0.10)
    static let selectionRing = accent

    /// Selected tiles lift with a soft accent glow — website `0 12px 34px rgba(93,109,255,.3)`.
    static let glowColor = accent
    static let glowOpacity: Float = 0.34
    static let glowRadius: CGFloat = 17
    static let glowOffset = CGSize(width: 0, height: -8)

    static let titlePrimary = NSColor(srgbRed: 0xEC / 255, green: 0xED / 255, blue: 0xF1 / 255, alpha: 1)
    static let titleSecondary = NSColor(srgbRed: 0x9B / 255, green: 0x9E / 255, blue: 0xA9 / 255, alpha: 1)

    static let thumbRadius: CGFloat = 10
    static let thumbBorder = NSColor.white.withAlphaComponent(0.07)
    static let thumbFill = NSColor.black.withAlphaComponent(0.30)

    static let spacing: CGFloat = 12
    static let maxColumns = 5
  }

  // MARK: The 1…9 index chip (top-left of every tile)

  enum Index {
    static let size: CGFloat = 20
    static let inset: CGFloat = 6
    static let radius: CGFloat = 5
    static let fill = NSColor(srgbRed: 8 / 255, green: 9 / 255, blue: 12 / 255, alpha: 0.7)
    static let selectedText = NSColor.white
    static let text = NSColor.white.withAlphaComponent(0.6)
    static let fontSize: CGFloat = 11
  }

  // MARK: Action chips on the selected tile (↓ here · W · Q)

  enum Chip {
    static let size: CGFloat = 19
    static let inset: CGFloat = 6
    static let gap: CGFloat = 5
    static let radius: CGFloat = 5
    static let fontSize: CGFloat = 9
    static let fill = NSColor(srgbRed: 8 / 255, green: 9 / 255, blue: 12 / 255, alpha: 0.78)
    static let border = NSColor.white.withAlphaComponent(0.18)
    static let glyph = NSColor.white
    static let hereFill = accent.withAlphaComponent(0.92)
    static let hereWidth: CGFloat = 46  // the wider "↓ here" pill
  }

  // MARK: The status badge inside a thumbnail (Minimized / Fullscreen)

  enum WindowBadge {
    static let fill = NSColor(srgbRed: 8 / 255, green: 9 / 255, blue: 12 / 255, alpha: 0.7)
    static let text = NSColor(srgbRed: 0xCF / 255, green: 0xD2 / 255, blue: 0xDC / 255, alpha: 1)
    static let fontSize: CGFloat = 9
    static let height: CGFloat = 16
    static let hPad: CGFloat = 6
  }

  /// CATextLayer needs an explicit scale or it renders blurry on Retina.
  static let textScale: CGFloat = 2

  // MARK: Fonts (native equivalents of the website's Schibsted Grotesk + JetBrains Mono)

  /// UI / display text — the system grotesque.
  static func ui(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
  }
  /// Keys / config / labels — the system monospace (stands in for JetBrains Mono).
  static func mono(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
    NSFont.monospacedSystemFont(ofSize: size, weight: weight)
  }
}
