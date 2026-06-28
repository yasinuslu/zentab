# ZenTab

A free, opinionated macOS window switcher (alternative to Cmd+Tab and
alt-tab-macos). SwiftUI scaffold today; the real app is a window switcher.

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

See `README.md`. Use `bin/run`, `bin/build`, `bin/test`, `bin/format`. Develop in
Zed (no Xcode GUI required). The `bin/*` scripts wrap `xcodebuild` and clear the
`LD` env var that otherwise breaks linking.
</content>
