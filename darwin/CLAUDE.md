# ZenTab

A free, opinionated macOS window switcher (alternative to Cmd+Tab and
alt-tab-macos). The first vertical slice is implemented: a menu bar accessory that,
on a safe hotkey (default `Ctrl+Opt+Tab`), enumerates other apps' current-Space
windows, shows a non-activating AppKit overlay, and focuses on release. See
`VISION.md` "Status" for what's done vs. next.

## Read this first

**[`VISION.md`](VISION.md) is the authoritative product direction. Read it before
proposing or building anything.** It defines the three-shortcut model, the
tap-vs-hold / stable-list behavior, and the non-negotiable principles
(performance first, opinionated and minimal, config-as-a-TOML-file, free forever).
Do not reintroduce ideas it rules out (no Pro tier, no settings sprawl, no MRU
reshuffling, no App Sandbox).

## Reference

alt-tab-macos (the app ZenTab reimagines) is cloned locally for source reference
when we need private SkyLight/CGS API names, edge cases, or performance techniques:
`~/code/.profile/yasinuslu/github/lwouis/alt-tab-macos`. It is GPL-3.0: read it for
facts and API names, do not copy its code into ZenTab.

## Build and test

See `README.md`. Use `bin/run`, `bin/build`, `bin/test`, `bin/format`, `bin/lint`.
Develop in Zed (no Xcode GUI required). The `bin/*` scripts wrap `xcodebuild` and
clear the `LD` env var that otherwise breaks linking.

**`project.yml` is the source of truth; `ZenTab.xcodeproj` is generated from it.**
Sources are discovered by directory, so a new `.swift` file just needs `bin/generate`
(never hand-edit the `.pbxproj`, and avoid changing build settings in the Xcode GUI:
a regenerate overwrites them). Put build settings, Info.plist keys, and entitlement
changes in `project.yml` / `ZenTab.entitlements`, then `bin/generate` and commit both.

## Private APIs

Private SkyLight/CGS + Accessibility SPIs are declared with `@_silgen_name` (no
bridging header) in `ZenTab/Private/`; SkyLight is linked via `-framework SkyLight`
(set in `project.yml`). A `@_silgen_name` signature is an unchecked C-ABI contract:
transcribe arg widths/order/return exactly, and smoke-test new symbols via the menu
bar "Run private-API diagnostics" action before using them in the hot path. App
Sandbox is OFF; hardened runtime keeps `disable-library-validation`.
</content>
