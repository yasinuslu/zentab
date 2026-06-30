# ZenTab

The alt-tab I always wanted: opinionated, instant, and the same on every OS I refuse to
leave. One window switcher, one product vision, two native implementations that live
together in this repository. Born from years of a great Linux switching experience that
neither macOS nor Windows ever matched — the [full origin story](darwin/README.md#why-zentab-exists)
is in the macOS readme.

| Platform | Folder | Stack | Status |
| --- | --- | --- | --- |
| **macOS** | [`darwin/`](darwin/) | Swift / AppKit, private SkyLight + Accessibility SPIs | the original; vertical slice working |
| **Windows** | [`windows/`](windows/) | C# / WPF on .NET 10, thin Win32/DWM interop | brought in from `zentab-windows` |

Both share the same idea: switch **individual windows** through a hand-rolled,
non-activating overlay driven by a global hotkey, ship with strong defaults, and keep the
entire configuration in one file you own. No Pro tier, no settings maze, free forever.
**One license, one vision, one product — two native apps.**

## Where to start

- **[`VISION.md`](VISION.md)** — the single, authoritative product direction for both apps
  (the three-mode model, tap-vs-hold, the principles). Read it first.
- **[`BRANDING.md`](BRANDING.md)**: the shared visual identity both apps transcribe (the
  always-dark spotlight, the Electric `#5D6DFF` accent, the card/tile/fade tokens).
- **macOS** — [`darwin/README.md`](darwin/README.md). Build/run with the `darwin/bin/*`
  scripts (`bin/run`, `bin/build`, `bin/test`).
- **Windows** — [`windows/README.md`](windows/README.md). Build/run with the PowerShell
  scripts (`windows/dev.ps1`, `windows/build.ps1`).

The shared `VISION.md`, `BRANDING.md`, `CLAUDE.md`, and `LICENSE` live at the root; each app
keeps only a platform-specific `README` in its folder.

## Repository layout

```
darwin/    macOS app (Swift) — sources, bin/ scripts, docs, project.yml
windows/   Windows app (C#/WPF) — sources, build.ps1/dev.ps1, installer/
.github/   CI + release workflows for both platforms (see below)
VISION.md · BRANDING.md · CLAUDE.md · LICENSE   shared across both apps
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

The whole repository — both apps — is **GPL-3.0** (single root [`LICENSE`](LICENSE)), the
same license as [alt-tab-macos](https://github.com/lwouis/alt-tab-macos), the project ZenTab
learns from. That clears porting alt-tab's window-engine techniques. You are free to use,
study, modify, and redistribute under the same terms.
