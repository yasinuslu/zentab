# ZenTab

The alt-tab I always wanted: opinionated, instant, and the same on every OS I refuse to leave.

ZenTab is one window switcher with two native implementations that live together in this
repository: this **macOS** app (Swift) and a **Windows** app (C#/WPF, in
[`../windows/`](../windows/)). Both share the same idea: switch individual windows through a
hand-rolled, non-activating overlay driven by a global hotkey, ship with strong defaults,
and keep the entire configuration in one file you own. No Pro tier, no settings maze, free
forever.

**Read [`../VISION.md`](../VISION.md) for the product direction** (the three-mode model,
tap-vs-hold, the stable list, the non-negotiable principles). Everything below this intro
covers the macOS app: how to run, build, and ship it.

## Why ZenTab exists

I had a phenomenal alt-tab experience on Linux for years. A handful of GNOME Shell
extensions and small switcher apps just nailed it: fast, predictable, the way switching
windows is supposed to feel. I never got that on macOS or Windows. Windows still has
nothing good; you can pay real money and still not get it. On macOS,
[alt-tab-macos](https://github.com/lwouis/alt-tab-macos) finally came close, and for a
long time it was what I used.

But it came with friction I could never fully get past:

- **It needed heavy configuration**, and I could never reliably persist it. I recently
  reinstalled my Mac, and the settings were old enough that I couldn't remember which
  toggles I'd flipped to get the behavior I wanted. There was no clean way to declare it
  and bring it back.
- **The one feature I rely on most, multiple shortcuts, became a Pro feature.** The
  price is fair and I'm happy to pay it; that isn't the problem. The problem is that
  paying still doesn't get me exactly the behavior I want, and I'd have to rebuild the
  whole config from memory anyway.
- **It wouldn't dependably own Cmd+Tab.** I want it to replace the native Cmd+Tab, and
  after every restart I had to go back into settings and re-register the shortcuts. That
  reliability, owning the key and holding it, is the single thing that matters most to
  me, and it was never solid.

So this is the alt-tab I want, built the way I want it: it works flawlessly, it ships
with opinionated defaults that encode how I think a switcher should behave in an OS, and
its configuration is a single file I can declare, check into git, and restore in
seconds. And it covers the two operating systems I can't stop using: **Windows for
gaming, macOS for building.** Both versions live in this one repository, each in its own
folder and built on its platform's native technologies (Swift on macOS, native Windows
tooling on Windows), sharing the same opinions about how a switcher should behave.

This is deep work. Getting a window switcher to feel instant and to reliably claim
system shortcuts across every app, Space, and OS quirk is genuine craftsmanship and a
large time investment, which is exactly why I never had the bandwidth for it before now.
Two things changed that. First, the original alt-tab-macos authors did years of hard
research into the private macOS internals this requires, and I get to learn from all of
it (see [Credits](#credits)). Second, building alongside Claude let me finally take it
to the finish line in a realistic amount of time. Huge thanks on both counts.

## What it does today

> **Status:** the first vertical slice is in (macOS). It binds the **Cmd+Tab suite** by
> default (`Cmd+Tab` every window here, `Cmd+\`` this app, `Option+Tab` everything),
> replacing the native macOS switchers while it runs. On the trigger it enumerates every
> window on the monitor under the mouse (current Space), shows a non-activating overlay
> grid, navigates with Tab / Shift+Tab and the mouse, and focuses on release (a quick
> tap switches to the previous window). The menu bar icon shows whether ZenTab currently
> owns the shortcut; it never silently falls back to another key, and it restores the
> native shortcut when it can't capture or on quit/crash. It runs as a menu bar accessory
> (no Dock icon). `bin/run` launches with safe `Ctrl+Opt+…` dev chords; `bin/run-prod`
> uses the real Cmd+Tab suite. See [Permissions](#permissions) for what to grant.

Built on Swift 6 with Swift Testing and a GitHub Actions release pipeline. The
switching behavior is fixed and opinionated; only the trigger keys are configurable.

## Requirements

- **macOS 15 or newer** (the app targets macOS 15.0)
- **Xcode 26 or newer**, installed from the App Store. Xcode has to be present (Swift and
  the macOS SDK live inside it), but you do not have to develop _in_ it; see
  "Develop in Zed" below.
- **`xcode-select` must point at Xcode, not the Command Line Tools.** The `bin/*` scripts
  call `xcodebuild`, which only works against full Xcode. If you see
  `tool 'xcodebuild' requires Xcode`, point it at Xcode once (a CLT update can silently
  flip this back):
  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```
  The scripts detect this case and print the exact command, so you don't have to remember
  it.
- Optional CLI helpers: `bin/setup` (or `brew bundle`) installs SwiftLint, xcbeautify, and
  xcode-build-server.

## Quick start (Xcode)

```bash
open ZenTab.xcodeproj   # then press Cmd+R to run, Cmd+U to test
```

`ZenTab.xcodeproj` is a normal, committed Xcode project: no generators, no extra setup.

## Develop in Zed (no Xcode GUI)

Prefer your editor? You can do everything except live Previews without opening Xcode.

1. One-time setup (installs tools, builds once, writes `buildServer.json`):
   ```bash
   bin/setup
   ```
2. Open this folder in **Zed** and install the **Swift** extension (`Cmd+Shift+X`, search
   "Swift"). It brings the SourceKit-LSP language server plus LLDB debugging.
3. Edit, then run `bin/run` / `bin/test` from Zed's terminal.

`buildServer.json` (generated by `xcode-build-server`) points SourceKit-LSP at the Xcode
project, so you get full autocomplete, inline errors, and jump-to-definition. After adding
files or changing build settings, run `bin/generate` to refresh the project (and re-run
`bin/setup` if the LSP needs the updated build settings).

**The one thing you lose vs. Xcode:** live **SwiftUI Previews** (the canvas that
re-renders as you type). Replacement loop: edit, `bin/run`, see the window (about 2
seconds for an app this small). A nice middle path: live in Zed, and open Xcode only when
you want the Preview canvas for a tricky view.

> If Zed can't find the language server, add this to your Zed settings (`Cmd+,`):
>
> ```json
> {
>   "lsp": {
>     "sourcekit-lsp": {
>       "binary": { "path": "/usr/bin/xcrun", "arguments": ["sourcekit-lsp"] }
>     }
>   }
> }
> ```

## Testing

Tests live in `ZenTabTests/` and use **Swift Testing** (`import Testing`, `@Test`,
`#expect`), the modern default in Xcode 16+. The pattern here is the recommended one: keep
the real decisions in small, UI-free value types and test those directly. The switcher's
logic lives in `SwitcherSelection` (the stable-list cursor), `Keybinding` (chord
parsing/matching), `Config` + `TOMLParser`, and `WindowInfo.isSwitchable`; the AppKit /
Accessibility / SkyLight shell (event tap, overlay, enumeration, focus) needs granted
permissions and is verified by hand.

```bash
bin/test        # build + run the full suite (the command CI runs)
```

## Command-line helpers

Thin wrappers around `xcodebuild` so the terminal and CI run identical commands:

| Command                 | What it does                                                                                    |
| ----------------------- | ----------------------------------------------------------------------------------------------- |
| `bin/setup`             | One-time: install tools, generate the project, build once, write `buildServer.json`             |
| `bin/generate`          | Regenerate `ZenTab.xcodeproj` from `project.yml` (after adding files / changing settings)        |
| `bin/run`               | Build (Debug) and launch with **safe dev shortcuts** (`Ctrl+Opt+…`); never touches your Cmd+Tab |
| `bin/run-prod`          | Build (Debug) and launch with the **production Cmd+Tab suite** (what the shipped app does)       |
| `bin/build`             | Debug build                                                                                      |
| `bin/test`              | Build + run the test suite                                                                       |
| `bin/lint`              | SwiftLint (config: `.swiftlint.yml`)                                                             |
| `bin/format`            | Format all Swift with `swift-format` (config: `.swift-format`)                                   |
| `bin/release <version>` | Build a Release `.app` and package `dist/*.dmg` + `*.zip`                                         |

> Heads up: a `LD=ld` export in some Nix/home-manager shells makes raw `xcodebuild` use
> the wrong linker. The `bin/*` scripts clear it automatically, so prefer them over calling
> `xcodebuild` directly in your terminal. Xcode's GUI is unaffected.

## Releasing

Releases are automated by `.github/workflows/release.yml`. To cut one:

```bash
git tag v0.1.0
git push origin v0.1.0
```

CI builds the app, packages a `.dmg` + `.zip`, and publishes a GitHub Release with both
attached. Builds are currently **ad-hoc signed (not notarized)**, so users get a
Gatekeeper warning on first launch; see [`docs/HUMAN-TODO.md`](docs/HUMAN-TODO.md) to add
real signing and notarization.

## Permissions

ZenTab is **not** sandboxed (it uses private SkyLight/CGS + Accessibility SPIs; this also
rules out the Mac App Store, by design). On first run, grant:

- **Accessibility** (mandatory): the global hotkey event tap and window reads need it. The
  menu bar item offers a "Grant Accessibility…" button that opens the right Settings pane;
  ZenTab starts switching automatically once granted.
- **Screen Recording** (optional): enables live window thumbnails. Without it, tiles show
  the app icon + title and everything else still works.

The menu bar also has a **"Run private-API diagnostics"** action that smoke-tests the
private symbols in isolation, so a bad binding shows up there rather than in the hot path.

## Project layout

```
ZenTab/
  App/        ZenTabApp.swift (@main, MenuBarExtra), AppDelegate, AppModel, MenuBarContent
  Input/      Keybinding (pure), HotkeyTap (CGEventTap, tap-vs-hold)
  Window/     WindowInfo (pure), WindowEnumerator, WindowThumbnail, WindowFocuser
  Switcher/   SwitcherSelection (pure stable-list cursor)
  Overlay/    SwitcherPanel (NSPanel), TileGridView (CALayer grid), OverlayController
  Config/     Config (pure), TOMLParser (pure), ConfigStore
  Private/    SkyLight.swift, HIServicesSPI.swift (@_silgen_name private APIs)
  System/     Permissions.swift
  Resources/  config.toml (bundled default)
  ZenTab.entitlements           App Sandbox OFF + disable-library-validation
ZenTabTests/  Swift Testing unit tests (the pure types above)
bin/          CLI helpers (also used by CI)
.github/workflows/  ci.yml (build+test), release.yml (tagged releases)
project.yml   the source of truth; ZenTab.xcodeproj is generated from it
```

## Conventions worth knowing

- **`project.yml` is the source of truth**, and `ZenTab.xcodeproj` is generated from it
  (`bin/generate`). Sources are discovered by directory, so adding a `.swift` file needs no
  project edit. Change build settings, Info.plist keys, and entitlements in `project.yml`
  (and `ZenTab.entitlements`), then regenerate and commit both. Avoid editing build
  settings in the Xcode GUI: a regenerate would overwrite them.
- **Bundle identifier** is `org.nepjua.ZenTab`. Change it in `project.yml`.
- **App Sandbox is OFF** on purpose (the switcher needs private SkyLight/CGS + AX SPIs).
  Hardened runtime stays on with `disable-library-validation` so the binary can load
  `SkyLight.framework`. See `ZenTab.entitlements`.

## The four non-negotiables

A window switcher should:

1. **Register its shortcuts reliably.** Forcefully grab them, never silently fall back.
2. **Perform well.** Zero perceptible lag.
3. **Never make you fight a wall of settings.** The behavior is opinionated and fixed.
4. **Be nixifiable.** Configuration is a single TOML file you can declare and check into git.

That is the whole product: strong defaults, no configuration overload, owned by you.

## Credits

ZenTab stands on the shoulders of
[**alt-tab-macos**](https://github.com/lwouis/alt-tab-macos) by
[@lwouis](https://github.com/lwouis) and its contributors. It is a remarkable, deeply
polished window switcher, and ZenTab has learned an enormous amount from it: the private
SkyLight/CGS and Accessibility techniques for discovering and focusing windows across
Spaces, the window-filtering model, and the countless macOS edge cases they spent years
getting right. ZenTab is a deliberately focused, opinionated take on the same idea, and it
exists because of their work. Huge thanks.

## License

ZenTab is licensed under the **GNU General Public License v3.0** (the same license as
alt-tab-macos, the project it learns from) — repo-wide, across both platforms. See
[`../LICENSE`](../LICENSE). You are free to use, study, modify, and redistribute it under
the same terms.
