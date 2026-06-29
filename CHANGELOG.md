# Changelog

All notable changes to ZenTab (Windows) are documented here. Releases are tagged `v*`;
the GitHub Release for each tag carries the portable exe, the MSI, and `SHA256SUMS.txt`.

## [Unreleased]

### Added
- One-shot `build.ps1` producing both the portable single-file exe and the MSI, with
  `-Target` / `-Version`, version validation, native exit-code checks, WiX-v5 enforcement,
  and `SHA256SUMS.txt`.
- Placeholder app icon (`assets/zentab.ico` + `make-icon.ps1` generator), wired into the
  exe, the tray, and the MSI (ARP + shortcut).
- PerMonitorV2 DPI awareness (`app.manifest`).
- GitHub Actions: CI (build + publish smoke test on push/PR) and a tag-driven Release.
- `global.json` SDK pin; `docs/review-notes.md` review backlog.

### Changed
- The portable exe is now truly portable: shipped without `zentab.toml`
  (`CopyToPublishDirectory="Never"`), so it always uses the real Alt+Tab gestures.
- Smaller self-contained build (~72 → ~66 MB) via `InvariantGlobalization` and
  `SatelliteResourceLanguages=en`.
- MSI allows same-version reinstall (`AllowSameVersionUpgrades`).

## [0.1.0]
- Initial build: tray-resident Alt+Tab alternative with the three hard-coded modes, live
  DWM thumbnails, quick-tap instant switch, self-contained single-file exe, and WiX MSI.
