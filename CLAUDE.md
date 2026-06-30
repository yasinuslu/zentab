# ZenTab

One product, two native apps in one repository: a **macOS** app (Swift / AppKit, in
[`darwin/`](darwin/)) and a **Windows** app (C# / WPF on .NET 10, in [`windows/`](windows/)).
Same vision and branding, native guts on each OS.

## Read this first

**[`VISION.md`](VISION.md) is the authoritative product direction. Read it before proposing
or building anything**, on either platform. It defines the three-mode model and its scopes,
the tap-vs-hold / stable-list behavior, and the non-negotiable pillars (feel + performance,
opinionated and minimal, config-as-a-TOML-file,
free forever). ZenTab is **very opinionated**: the default answer to "should this be a
setting?" is **no**. When a request conflicts with VISION.md, surface the tension instead of
silently implementing it. Do not reintroduce ideas it rules out (no Pro tier, no settings
sprawl, no MRU reshuffling).

**[`BRANDING.md`](BRANDING.md) is the authoritative visual identity** — the one brand both
apps share (the always-dark "spotlight" scrim, the dim+blur recede, the ZenTab Electric
accent #5D6DFF, the card/tile/fade tokens). Change a brand value there first, then transcribe it into each
app's theme code (macOS: `darwin/ZenTab/Overlay/OverlayTheme.swift`). Keep the two apps
looking like the same product — don't fork the brand per OS.

## Repository layout

```
darwin/    macOS app (Swift) — sources, bin/ scripts, docs, project.yml
windows/   Windows app (C#/WPF) — sources, build.ps1/dev.ps1, installer/
.github/   CI + release workflows for both platforms (path-scoped)
```

Shared at the root: `VISION.md`, `BRANDING.md`, this `CLAUDE.md`, `LICENSE` (GPL-3.0), and
the monorepo `README.md`. Each app also keeps its own `README.md` with platform build/run
details.

## macOS (`darwin/`)

Work from `darwin/`. Build/test with `darwin/bin/*`: `bin/run`, `bin/build`, `bin/test`,
`bin/format`, `bin/lint`. Develop in Zed (no Xcode GUI required). The `bin/*` scripts wrap
`xcodebuild` and clear the `LD` env var that otherwise breaks linking.

- **`project.yml` is the source of truth; `ZenTab.xcodeproj` is generated from it.** Sources
  are discovered by directory, so a new `.swift` file just needs `bin/generate` (never
  hand-edit the `.pbxproj`, and avoid changing build settings in the Xcode GUI — a
  regenerate overwrites them). Put build settings, Info.plist keys, and entitlement changes
  in `project.yml` / `ZenTab.entitlements`, then `bin/generate` and commit both.
- **Private APIs.** Private SkyLight/CGS + Accessibility SPIs are declared with
  `@_silgen_name` (no bridging header) in `ZenTab/Private/`; SkyLight is linked via
  `-framework SkyLight` (set in `project.yml`). A `@_silgen_name` signature is an unchecked
  C-ABI contract: transcribe arg widths/order/return exactly, and smoke-test new symbols via
  the menu bar "Run private-API diagnostics" action before using them in the hot path. App
  Sandbox is OFF; hardened runtime keeps `disable-library-validation`.

## Windows (`windows/`)

Work from `windows/`. C# / WPF on .NET 10 with a thin Win32/DWM interop layer (`Native.cs`).
Build/run with `dotnet run`, `./dev.ps1`, and `./build.ps1` (portable exe + WiX MSI +
checksums into `dist/`). See `windows/README.md` for details. The low-level keyboard hook
sits in the system input path — keep its callback off the hot path (see VISION.md's
performance pillar).

## Reference

alt-tab-macos (the app ZenTab reimagines) is cloned locally for source reference when we
need private SkyLight/CGS API names, edge cases, or performance techniques:
`~/code/.profile/yasinuslu/github/lwouis/alt-tab-macos`. It is GPL-3.0: read it for facts
and API names, do not copy its code into ZenTab.

## CI and releases

Workflows live at the repo root and are **path-scoped**: a `darwin/**` change runs only the
macOS jobs, a `windows/**` change only the Windows jobs. Release tags are namespaced per
platform so they don't collide: `darwin-v*` cuts a macOS release, `windows-v*` a Windows one.

Bundles ship to the `nepjua-cdn` R2 bucket (`cdn.nepjua.org`), not to GitHub assets:
`*-main.yml` overwrite a rolling "latest from main" copy on every push to `main`, and
`*-release.yml` upload versioned + "latest stable" copies on a tag (the GitHub Release is
notes-only). Uploads go through `darwin/bin/r2-publish` / `windows/r2-publish.ps1` (curl
SigV4), driven by the `R2_API_URL`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` secrets. See
the README "Artifacts on R2" section for the object layout.

## License

The whole repo is **GPL-3.0** (single root [`LICENSE`](LICENSE)) — the same license as
alt-tab-macos, the project it learns from, which clears porting alt-tab techniques.
