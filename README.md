# ZenTab

A calm, native **macOS app built with SwiftUI** — a clean, modern starting point
you can grow into a real product. Swift 6, Swift Testing, and a GitHub Actions
release pipeline are wired up and working.

> New to macOS development? You only need two things to start: **open the project
> in Xcode and press ⌘R**. Everything below is here when you want it.

## Requirements

- **macOS 15 or newer** (the app targets macOS 15.0)
- **Xcode 26** or newer — install from the App Store
- Optional CLI helpers: `brew bundle` installs SwiftLint + xcbeautify

## Quick start

```bash
open ZenTab.xcodeproj   # then press ⌘R to run, ⌘U to test
```

That's the whole loop. `ZenTab.xcodeproj` is a normal, committed Xcode project —
no generators, no extra setup.

## The daily loop (good DX)

- **See changes live:** open any SwiftUI view (e.g. `ContentView.swift`) and use
  the **Canvas / Preview** (⌥⌘↩ to toggle). Edit the view and the preview updates
  as you type — the fastest way to iterate on UI.
- **Run the real app:** ⌘R. Changes appear on the next run.
- **Run tests:** ⌘U, or `bin/test` from a terminal.

<details>
<summary>Want true hot-reload of a <em>running</em> app? (optional, advanced)</summary>

SwiftUI Previews cover "design one view in isolation" well. If you later want to
inject code into the running app without restarting, the community standard is
[Inject](https://github.com/krzysztofzablocki/Inject) +
[InjectionNext](https://github.com/johnno1962/InjectionNext). It needs a Swift
package, a `-Xlinker -interposable` debug linker flag, and disabling the App
Sandbox + library validation in Debug. Skip it until you feel the need.
</details>

## Testing

Tests live in `ZenTabTests/` and use **Swift Testing** (`import Testing`,
`@Test`, `#expect`) — the modern default in Xcode 16+. The pattern here is the
recommended one: keep logic in small, UI-free types (see `FocusModel`) and test
those directly; cover real rendering with the app/Previews.

```bash
bin/test        # build + run the full suite (same command CI runs)
```

## Command-line helpers

Thin wrappers around `xcodebuild` so the terminal and CI run identical commands:

| Command | What it does |
| --- | --- |
| `bin/run` | Build (Debug) and launch the app |
| `bin/build` | Debug build |
| `bin/test` | Build + run the test suite |
| `bin/lint` | SwiftLint (config: `.swiftlint.yml`) |
| `bin/format` | Format all Swift with `swift-format` (ships with Xcode) |
| `bin/release <version>` | Build a Release `.app` and package `dist/*.dmg` + `*.zip` |

> Heads up: a `LD=ld` export in some Nix/home-manager shells makes raw
> `xcodebuild` use the wrong linker. The `bin/*` scripts clear it automatically,
> so prefer them over calling `xcodebuild` directly in your terminal. (Xcode's
> GUI is unaffected.)

## Releasing

Releases are automated by `.github/workflows/release.yml`. To cut one:

```bash
git tag v0.1.0
git push origin v0.1.0
```

CI builds the app, packages a `.dmg` + `.zip`, and publishes a GitHub Release
with both attached. Builds are currently **ad-hoc signed (not notarized)**, so
users get a Gatekeeper warning on first launch — see
[`docs/HUMAN-TODO.md`](docs/HUMAN-TODO.md) to add real signing + notarization.

## Project layout

```
ZenTab/
  App/        ZenTabApp.swift (@main), ContentView.swift
  Models/     FocusModel.swift  — UI-free, fully unit-tested
  Assets.xcassets/
  ZenTab.entitlements           — App Sandbox enabled by default
ZenTabTests/  Swift Testing unit tests
bin/          CLI helpers (also used by CI)
.github/workflows/  ci.yml (build+test), release.yml (tagged releases)
project.yml   one-time scaffold spec (NOT the source of truth — see its header)
```

## Conventions worth knowing

- **`ZenTab.xcodeproj` is the source of truth.** Edit build settings in Xcode as
  normal; they persist. `project.yml` was only used to scaffold the project once.
- **Bundle identifier** is `org.nepjua.ZenTab` — change it in Xcode (target →
  Signing & Capabilities) if you prefer something else.
- **App Sandbox** is on (matches Xcode's template). If a feature needs file,
  network, or automation access, add the entitlement in `ZenTab.entitlements`.
