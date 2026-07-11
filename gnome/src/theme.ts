// Every color, radius, and metric the overlay draws, transcribed from the brand's single
// source of truth: /BRANDING.md (mirrored machine-readably at website/src/theme.css, and
// transcribed into the native apps at darwin/ZenTab/Overlay/OverlayTheme.swift and
// windows/App.xaml). Change a value in BRANDING.md FIRST, then mirror it here — this file
// must never invent its own numbers.
//
// GJS/St has no CSS blur filter and Clutter's blur effects are comparatively expensive, so
// v1 renders a plain dim scrim (see overlay.ts's `TODO(blur)` hook) rather than the
// website/macOS GPU blur-behind. Colors below are otherwise a faithful transcription.

/** The one brand color (BRANDING.md "Accent"). Marks the focused tile only — nothing else
 * competes with it. St/Clutter color strings take CSS-style `#rrggbb` / `rgba()`. */
export const ACCENT = "#5D6DFF";

export const COLOR = {
  bg: "#0B0C0F",
  bg2: "#101218",
  card: "rgba(24, 26, 33, 0.72)",
  border: "rgba(255, 255, 255, 0.075)",
  borderHi: "rgba(255, 255, 255, 0.14)",
  text: "#ECEDF1",
  dim: "#9B9EA9",
  faint: "#5E616C",
  accent: ACCENT,
  accentDim: "rgba(93, 109, 255, 0.16)",
} as const;

/** Always-dark spotlight scrim (BRANDING.md "Overlay tokens"). St has no blur filter today —
 * TODO(blur): once a GPU-backed blur-behind exists for St (ShellBlurEffect / a Clutter blur
 * node), composite it under this scrim the way the website's `blur(6px)` and macOS's
 * NSVisualEffectView do. Until then this is a flat, slightly-more-opaque dim so the overlay
 * still reads as "the world receded" without a blur. */
export const BACKDROP = {
  scrim: "rgba(6, 7, 10, 0.55)",
  // TODO(blur): remove once a real blur-behind lands; compensates for the missing blur by
  // leaning darker so unblurred desktop content doesn't visually compete with the card.
  scrimFallbackOpaque: "rgba(6, 7, 10, 0.86)",
} as const;

export const CARD = {
  radius: 24,
  padding: 22,
  fill: COLOR.card,
  border: "rgba(255, 255, 255, 0.12)",
  borderWidth: 1,
  shadowColor: "rgba(0, 0, 0, 0.6)",
  minContentWidth: 820,
} as const;

export const TILE = {
  width: 196,
  height: 158,
  radius: 15,
  borderWidth: 2,
  fillUnselected: "rgba(255, 255, 255, 0.02)",
  selectedRingColor: ACCENT,
  selectedWash: "rgba(93, 109, 255, 0.10)",
  selectedGlow: "0 12px 34px rgba(93, 109, 255, 0.3)",
  thumbnailRadius: 10,
  thumbnailBorder: "rgba(255, 255, 255, 0.07)",
  // Fixed size of the live-preview box inside each tile (a Clutter.Clone of the window actor
  // is scaled to fit within this, preserving aspect ratio; leftover space is the dark box).
  thumbnailWidth: 172,
  thumbnailHeight: 80,
  // darwin/ZenTab/Overlay/OverlayTheme.swift Tile.spacing / Tile.maxColumns — the flow-grid
  // metrics the v1 St.BoxLayout grid wraps rows at (no CSS grid in St/Clutter).
  spacing: 12,
  maxColumns: 5,
  // darwin's Tile.iconSize / titleSize (the footer row's app-icon + title, the only
  // identifying content a no-thumbnail v1 tile has).
  iconSize: 28,
  titleSize: 13,
} as const;

export const INDEX_CHIP = {
  size: 18,
  radius: 5,
  fill: "rgba(8, 9, 12, 0.7)",
  textDim: "rgba(255, 255, 255, 0.6)",
  textSelected: "#FFFFFF",
} as const;

/** W (close) / Q (quit) affordances shown on the focused tile — VISION: exactly these two. */
export const ACTION_CHIP = {
  size: 19,
  radius: 5,
  fill: "rgba(8, 9, 12, 0.78)",
  border: "rgba(255, 255, 255, 0.18)",
  glyph: "#FFFFFF",
} as const;

export const KEY_PILL = {
  border: "rgba(93, 109, 255, 0.35)",
  radius: 7,
  text: ACCENT,
  fontSize: 12, // darwin OverlayTheme.Header.pillSize
  hPad: 9, // darwin OverlayTheme.Header.pillHPad
} as const;

export const HAIRLINE = "rgba(255, 255, 255, 0.08)";

/** The card's header strip: key pill · mode label · window count (darwin OverlayTheme.Header). */
export const HEADER = {
  labelSize: 15,
  labelColor: COLOR.text,
  countSize: 11,
  countColor: COLOR.faint,
  gap: 12, // between the key pill and the mode label
  bottomGap: 18, // between the header and the tile grid below it
} as const;

/** Quick and soft, never slow (VISION's performance pillar). */
export const MOTION = {
  fadeDurationMs: 100, // BRANDING.md: fades ~80-120ms
  summonScaleFrom: 0.97,
  // BRANDING.md's cubic-bezier(0.22, 0.61, 0.36, 1), expressed as a Clutter easing mode.
  // Clutter.AnimationMode.EASE_OUT_QUAD/EASE_OUT_CUBIC are the closest stock modes; a custom
  // Clutter.AnimationMode.CUBIC_BEZIER (with cubic-bezier() progress callback) matches exactly
  // if precision here ends up mattering once the overlay's real reveal animation is built.
  easeControlPoints: [0.22, 0.61, 0.36, 1] as const,
} as const;

/** Typography stand-ins (BRANDING.md: web fonts on the left, native fallbacks on the right —
 * GNOME has neither Schibsted Grotesk nor JetBrains Mono installed by default, so we fall
 * back to the desktop's own UI/monospace stacks, consistent with how the Windows app falls
 * back to Segoe UI / Consolas when its preferred fonts aren't present). */
export const FONT = {
  ui: "Cantarell, sans-serif",
  mono: "monospace",
} as const;
