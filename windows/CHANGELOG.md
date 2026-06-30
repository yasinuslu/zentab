# Changelog

All notable changes to ZenTab (Windows) are documented here. Releases are tagged
`windows-v*`; the GitHub Release for each tag carries the portable exe, the MSI, and
`SHA256SUMS.txt`.

## [Unreleased]

### Added
- One-shot `build.ps1` producing both the portable single-file exe and the MSI, with
  `-Target` / `-Version`, version validation, native exit-code checks, WiX-v5 enforcement,
  and `SHA256SUMS.txt`.
- The canonical ZenTab brand mark as the app icon (`assets/zentab.svg` → `zentab.ico` via
  `make-icon.ps1`), wired into the exe, the tray, and the MSI (ARP + shortcut).
- Overlay chrome matching the macOS app: a header (trigger key pill, mode label, count), a
  footer hint row, per-tile 1-9 index chips, and W/Q action chips on the focused tile.
- GPU acrylic blur behind the dim layer (`SetWindowCompositionAttribute`) with the website
  spotlight scrim and a radial-gradient dim.
- A real TOML config: `%APPDATA%\zentab\config.toml` (or a portable `zentab.toml`) with
  `[keys]` trigger chords and `[behavior] hold_threshold_ms`; 1-9 keys jump to a tile.
- PerMonitorV2 DPI awareness (`app.manifest`).
- GitHub Actions: CI (build + publish smoke test on push/PR) and a tag-driven Release.
- `global.json` SDK pin; `docs/review-notes.md` review backlog.

### Fixed
- Phantom system windows (e.g. "Windows Input Experience"/TextInputHost) no longer appear
  in the switcher; only genuinely Alt+Tab-switchable windows are shown.

### Changed
- The portable exe is now truly portable: shipped without `zentab.toml`
  (`CopyToPublishDirectory="Never"`), so it always uses the real Alt+Tab gestures.
- Smaller self-contained build (~72 → ~66 MB) via `InvariantGlobalization` and
  `SatelliteResourceLanguages=en`.
- MSI allows same-version reinstall (`AllowSameVersionUpgrades`).
- Brand: replaced the Catppuccin Mocha palette with the canonical website/macOS tokens
  (accent Electric `#5D6DFF`); see [`../BRANDING.md`](../BRANDING.md).
- In-overlay actions are now **W** (close window) / **Q** (quit app), replacing Delete /
  Shift+Delete, per VISION.md.
- Quick-tap hold threshold now defaults to 150 ms (was a hardcoded 200 ms) and is
  configurable via `hold_threshold_ms`.

## [0.1.0]
- Initial build: tray-resident Alt+Tab alternative with the three hard-coded modes, live
  DWM thumbnails, quick-tap instant switch, self-contained single-file exe, and WiX MSI.
