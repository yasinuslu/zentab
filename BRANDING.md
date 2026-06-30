# ZenTab — Branding

The one visual identity both apps share. ZenTab is **one product**: the macOS app
([`darwin/`](darwin/)) and the Windows app ([`windows/`](windows/)) must look like the same
thing, not two interpretations of it. This file is the **authoritative brand**; change a
value here first, then transcribe it into each app's theme code. Don't fork the brand per OS.

The machine-readable mirror of these tokens lives in
[`website/src/theme.css`](website/src/theme.css) and the playable overlay in
`website/src/pages/Overlay.tsx`; the native apps transcribe from the same numbers
(macOS: `darwin/ZenTab/Overlay/OverlayTheme.swift`; Windows: `windows/App.xaml`,
`windows/DimWindow.cs`).

## The idea: a spotlight

The switcher is a moment where **the rest of the world recedes** (VISION.md). So the overlay
is an **always-dark spotlight**, regardless of the OS light/dark theme: the world behind dims
and blurs, a single frosted card holds the choices, and **one** accent marks the one window
in focus. Calm, not stimulating; quiet chrome; soft, quick motion.

## Accent

**Electric — `#5D6DFF`.** The single brand color, used like one held note: it marks the
focused tile (ring, wash, glow), the trigger key pill, and the focused tile in the app icon.
Nothing else competes with it. There is no second hue.

## Color tokens

From `website/src/theme.css` (`#RRGGBB`, or `rgba()` where alpha matters):

| Token | Value | Use |
| --- | --- | --- |
| `--bg` | `#0B0C0F` | near-black backdrop / letterbox |
| `--bg2` | `#101218` | raised surface |
| `--card` | `rgba(24,26,33,0.72)` | the frosted card over the blurred backdrop |
| `--bd` | `rgba(255,255,255,0.075)` | hairline border |
| `--bdhi` | `rgba(255,255,255,0.14)` | hover/strong border |
| `--tx` | `#ECEDF1` | primary text |
| `--dim` | `#9B9EA9` | secondary / unselected text |
| `--faint` | `#5E616C` | tertiary text, counts |
| `--accent` | `#5D6DFF` | the one accent (Electric) |
| `--accentdim` | `rgba(93,109,255,0.16)` | selection wash behind a focused tile |

## Overlay tokens

- **Spotlight scrim:** `rgba(6,7,10,0.55)` over a **GPU blur** of the world (`blur(6px)` on
  the web; acrylic/DWM on Windows, `NSVisualEffectView` on macOS). On macOS, where no real
  desktop shows through, the scrim is baked into a near-opaque radial gradient
  (inner `rgba(18,28,41,0.82)` → outer `rgba(6,7,10,0.86)`); on Windows the real blurred
  desktop shows, so the dim leans lighter and rides on the blur.
- **Card:** fill `rgba(24,26,33,0.72)`, border `rgba(255,255,255,0.12)`, radius `24`,
  padding `22`, soft black drop shadow. (Windows paints the card opaque `#181A21` because DWM
  live thumbnails can't render on a transparent window; the blur is the separate dim layer.)
- **Tile:** `196×158`, radius `15`, 2px border. Unselected fill `rgba(255,255,255,0.02)`;
  **selected** = accent ring (2px) + wash `rgba(93,109,255,0.10)` + soft accent glow
  (`0 12px 34px rgba(93,109,255,0.3)`). Thumbnail radius `10`, border `rgba(255,255,255,0.07)`.
- **Index chip (1…9):** `18px`, radius `5`, fill `rgba(8,9,12,0.7)`, text white@0.6
  (white when selected).
- **Action chips (W · Q):** `19px`, radius `5`, fill `rgba(8,9,12,0.78)`,
  border `rgba(255,255,255,0.18)`, white glyph; shown on the focused tile.
- **Key pill:** accent text in an accent-outlined chip — border `rgba(93,109,255,0.35)`,
  radius `7`.
- **Dividers / hairlines:** `rgba(255,255,255,0.08)`.

## Typography

- **UI / display:** **Schibsted Grotesk** (web). Native stand-ins: the system grotesque on
  macOS; Segoe UI Variable (fallback Segoe UI) on Windows.
- **Keys / labels / config:** **JetBrains Mono** (web). Native stand-ins: the system
  monospace on macOS; Cascadia Mono (fallback Consolas) on Windows.

## Motion

Quick and soft, never slow (VISION's performance pillar): fades ~**80–120 ms**; the overlay
appears with a scale `0.97 → 1` on the ease `cubic-bezier(0.22, 0.61, 0.36, 1)`. No jank,
no per-frame CPU bitmap work; animate toward the display's real refresh.

## The brand mark (icon)

A **dark rounded-square body** (gradient `#1A1D28` → `#0D0E13`, ~22.5% corner radius), a
**steady white "switcher" frame** (the structure that's always there), and **one Electric
tile** (gradient `#7282FF` → `#5160FF`) offset into a corner — the window in focus, glowing.
Source: `windows/assets/zentab.svg` (Windows; rasterized to `zentab.ico`); the macOS app
renders the same mark in code.

## Changing a brand value

1. Edit the token here, and in `website/src/theme.css` (the machine-readable mirror).
2. Transcribe into each app: macOS `darwin/ZenTab/Overlay/OverlayTheme.swift`; Windows
   `windows/App.xaml` (+ `windows/DimWindow.cs` for the backdrop).
3. Keep the two apps looking like the same product.
