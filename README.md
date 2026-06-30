# ZenTab

The alt-tab I always wanted: opinionated, instant, and the same on every OS I refuse to
leave. One window switcher, one product vision, two native implementations that live
together in this repository.

| Platform | Folder | Stack | Status |
| --- | --- | --- | --- |
| **macOS** | [`darwin/`](darwin/) | Swift / AppKit, private SkyLight + Accessibility SPIs | the original; vertical slice working |
| **Windows** | [`windows/`](windows/) | C# / WPF on .NET 10, thin Win32/DWM interop | brought in from `zentab-windows` |

Both share the same idea: switch **individual windows** through a hand-rolled,
non-activating overlay driven by a global hotkey, ship with strong defaults, and keep the
entire configuration in one file you own. No Pro tier, no settings maze, free forever.
Same philosophy, same branding, different native guts.

## Where to start

- **macOS** — see [`darwin/README.md`](darwin/README.md) and [`darwin/VISION.md`](darwin/VISION.md).
  Build/run with the `darwin/bin/*` scripts (`bin/run`, `bin/build`, `bin/test`).
- **Windows** — see [`windows/README.md`](windows/README.md) and [`windows/VISION.md`](windows/VISION.md).
  Build/run with the PowerShell scripts (`windows/dev.ps1`, `windows/build.ps1`).

Each platform keeps its own `README`, `VISION`, and `CLAUDE.md` in its folder — read those
before working on that platform.

## Repository layout

```
darwin/    macOS app (Swift) — sources, bin/ scripts, docs, project.yml
windows/   Windows app (C#/WPF) — sources, build.ps1/dev.ps1, installer/
.github/   CI + release workflows for both platforms (see below)
```

## CI and releases

The two platforms are independent in CI. Workflows are path-scoped, so a change under
`darwin/**` only runs the macOS jobs and a change under `windows/**` only runs the Windows
jobs:

- `darwin-ci.yml` / `windows-ci.yml` — build + test on PRs and pushes to `main`.
- `darwin-release.yml` / `windows-release.yml` — publish a GitHub Release on a tag.

Release tags are **namespaced per platform** so they don't collide:

```
git tag darwin-v0.1.0  && git push origin darwin-v0.1.0     # cuts a macOS release
git tag windows-v0.2.0 && git push origin windows-v0.2.0    # cuts a Windows release
```

## License

The two implementations carry different licenses (kept in their folders):

- **macOS** (`darwin/`) — **GPL-3.0** (see [`darwin/LICENSE`](darwin/LICENSE)); it ports
  window-engine techniques from [alt-tab-macos](https://github.com/lwouis/alt-tab-macos).
- **Windows** (`windows/`) — **MIT** (see [`windows/LICENSE`](windows/LICENSE)).
