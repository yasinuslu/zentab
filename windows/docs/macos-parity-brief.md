# Windows → macOS parity brief

Bring the Windows app (`windows/`) up to date with the macOS app (`darwin/`): feature parity
where it matters, brand/UI parity exactly, a real icon, and refreshed docs. This file is the
authoritative spec for the parity pass. Work in the current worktree; push to branch
`windows/parity-with-macos` and open a PR when done.

## Calibration (decided)

1. **Scope** = "core parity + brand + icon + docs". Cross-virtual-desktop curation
   (summon/fling, zone heads) is **Phase 2 / feasibility-gated, NOT this PR** — Windows Virtual
   Desktop COM APIs are undocumented and fragile. Assess feasibility and write up findings
   (a short section in this doc or `review-notes.md`) instead of forcing it.
2. **BRANDING.md** = **create it**. Transcribe the website tokens into a real `BRANDING.md` at
   the repo root (CLAUDE.md already promises it as authoritative), then point both apps' theme
   code at it as the named source of truth.
3. **Verify** = CI + Yasin's local build. WPF/.NET 10 **cannot build on macOS**, so the app
   cannot be run in this session. Make the code correct by construction, lean on the Windows CI
   build job (push the branch), and flag in the PR that Yasin must run `./build.ps1` and
   smoke-test on Windows before merge. **Do NOT claim it is verified working.**

## Read first (source of truth — do not invent values)

- `VISION.md` — behavior model, the non-negotiable pillars, the "should this be a setting? no"
- `website/src/theme.css` + `website/src/pages/Overlay.tsx` — canonical brand tokens
- `darwin/ZenTab/Overlay/OverlayTheme.swift` — the faithful reference transcription to mirror
- `windows/App.xaml`, `windows/OverlayWindow.xaml(.cs)`, `windows/SwitcherController.cs`,
  `windows/KeyboardHook.cs` — current Windows state

## Workstreams

### A. Brand + theme (`windows/App.xaml`)
Replace the Catppuccin Mocha palette with the website/macOS tokens:

| Token | Current (Catppuccin) | Target (canonical) |
| --- | --- | --- |
| accent | `#B4B4BEFE` (Lavender) | `#5D6DFF` (Electric) |
| selection | lavender border | accent ring 2px + fill `rgba(93,109,255,0.16)` |
| panel / card | `#1E1E2E` | `rgba(24,26,33,0.72)` over the blurred backdrop |
| title (selected) | `#CDD6F4` | `~#ECEDF1` |
| title (unselected) | `#A6ADC8` | `#9B9EA9` |
| muted / faint | `#6C7086` | `#5E616C` |
| thumb placeholder | `#181825` | dark backing `rgba(0,0,0,0.30)` on bg `#0B0C0F` |

The one accent marks the focused tile only. No multi-hue palette.

### B. Backdrop
Replace the flat translucent dim with **GPU blur** (acrylic / DWM backdrop) + the website
spotlight scrim `rgba(6,7,10,0.55)` and a radial-gradient dim (inner `rgba(18,28,41,0.82)` →
outer `rgba(6,7,10,0.86)`). Keep it click-through and per-monitor. **This is the #1 visual gap.**

### C. Overlay chrome (match macOS layout)
Add the header (accent-outlined **key pill** with the trigger glyphs + centered **mode label**
"Other apps / Current app / Everything" + right-aligned **count**), the **footer hint row**,
per-tile **index chips** (1–9), and selected-tile **action chips**. Aim for macOS tile
proportions (~196×158, 15px radius, 2px border); minor platform tweaks are fine as long as the
brand tokens match. Bundle **Schibsted Grotesk** (UI) + **JetBrains Mono** (keys/labels) or use
the closest fallbacks (Segoe UI Variable / Cascadia Mono) and note the choice.

### D. In-overlay actions
Align to VISION: **W closes the window, Q quits the app.** Migrate off Delete / Shift+Delete.
No minimize / fullscreen / hide.

### E. Config
Make the TOML a **real shipped config** (not dev-only) at a standard path
(`%APPDATA%\zentab\config.toml`), with the same shape as macOS: `[keys] current_app /
other_apps / everything` + `[behavior] hold_threshold_ms` (default **150**, replacing the
hardcoded 200ms quick-tap). Keys are the only configurable surface — keep VISION's
no-settings-sprawl.

### F. Icon
Generate the canonical brand mark: dark rounded-square body, white outlined frame, one Electric
`#5D6DFF` tile offset into a corner, body gradient `#1A1D28` → `#0D0E13`. Replace the
placeholder; regenerate the multi-res `.ico` via the assets generator; wire into
exe / tray / MSI / Start-menu shortcut.

### G. Docs
Fix staleness: README + installer help link + CHANGELOG should reflect the **monorepo** (not a
standalone `zentab-windows` repo). Add a CHANGELOG entry for this parity pass. Create
`BRANDING.md` (knob 2) and reference it from both apps' READMEs.

## Constraints

- Honor `VISION.md`: opinionated, behavior is fixed, only trigger keys are configurable. If
  anything tempts a new setting or an MRU-reshuffling list, **stop and surface the tension.**
- **Don't fork the brand per OS** — match the canonical tokens, don't reinterpret them.
- Keep the low-level keyboard hook callback off the hot path (performance pillar).
- Commit incrementally with clear messages. This is **`darwin/`-untouched, `windows/**` only**
  (so CI runs just the Windows jobs).
- Open the PR with: a summary, the per-workstream changes, the Phase-2 feasibility notes, and
  the **"must build + smoke-test on Windows before merge"** caveat.
