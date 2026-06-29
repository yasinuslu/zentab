# Human-only TODO

Things the automation can't do for you, each needs an account, a secret, or a
personal decision. Nothing here blocks day-to-day development; the app builds,
runs, tests, and produces (unsigned) releases as-is.

## 0. Try the switcher (grant permissions + hand-verify the slice)

The first vertical slice is build- and test-verified, but its actual switching
behavior needs two TCC permissions that only you can grant, and a human at the
keyboard to confirm. The automation can't do this part.

- [ ] `bin/run` to launch ZenTab. It appears as a menu bar item (no Dock icon).
- [ ] From the menu bar, **Grant Accessibility…** and enable ZenTab in System
      Settings. It starts the switcher automatically once trusted (no relaunch).
- [ ] Optionally **Enable live thumbnails (Screen Recording)…**; without it, tiles
      show app icon + title.
- [ ] **Hold `Ctrl+Opt` and press `Tab`:** the overlay grid should appear after the
      hold threshold; `Tab` / `Shift+Tab` and the mouse move the selection; releasing
      `Ctrl+Opt` focuses the selected window. A quick `Ctrl+Opt+Tab` tap should switch
      with no overlay. `Esc` cancels.
- [ ] Test focus across a few app kinds (Safari, Terminal, an Electron app) since the
      private front/key sequence has app-specific edge cases.
- [ ] Run **"Run private-API diagnostics"** from the menu; it should print a non-zero
      CGS connection and a PSN (confirms the `@_silgen_name` bindings are sound).

### Then verify the real Cmd+Tab capture (production suite)

The above uses safe dev chords. To exercise the native-switcher override, launch the
production suite. This *replaces* the macOS Cmd+Tab while ZenTab runs, so it needs a
human to confirm it behaves and recovers correctly.

- [ ] `bin/run-prod` (quits any running ZenTab first, then relaunches owning Cmd+Tab).
- [ ] **Menu bar icon is the indicator:** a calm rectangle = ZenTab owns the shortcut;
      a warning triangle = it doesn't (open the menu for the reason). With Accessibility
      granted it should be the rectangle within ~2s.
- [ ] **Press `Cmd+Tab`:** ZenTab's overlay/switch should appear — *not* the macOS
      app switcher. Try `Cmd+\`` (this app) and `Option+Tab` (everything) too.
- [ ] **Restore-on-quit:** Quit ZenTab; native macOS `Cmd+Tab` should work again
      immediately. Relaunch; ZenTab reclaims it.
- [ ] **Restore-on-kill:** `pkill -x ZenTab` (or kill it in Activity Monitor); native
      `Cmd+Tab` should again be restored (SIGTERM guard), not left dead.
- [ ] **Watchdog re-assert:** while ZenTab runs, the menu bar should stay on the
      rectangle even if something briefly re-enables the native switcher (it re-claims
      on the next 2-second tick).

If something misbehaves, the runtime (event tap, overlay, enumeration, focus, native
hotkey claim) is the hand-verified shell; the pure logic — trigger→symbolic-hotkey
mapping, capture-health classification, launch-profile defaults — is covered by `bin/test`.

## 1. Signed + notarized releases (optional, recommended before public distribution)

Today `release.yml` ships an **ad-hoc-signed, un-notarized** `.dmg`. It runs, but
macOS Gatekeeper warns users on first launch (and on macOS 15+ they must go to
**System Settings → Privacy & Security → Open Anyway**). To remove that friction
you need an Apple Developer account and a few CI secrets.

> **Status (blocker).** Notarization is the committed end state for ZenTab (see
> `VISION.md`), but the Apple Developer account is currently stuck: the existing
> account is an *organization* account that Apple refuses to switch to
> *individual*, and that org no longer exists (a legal matter to untangle). Likely
> path is a new Apple ID, possibly under a different domain. Until it is resolved,
> releases stay ad-hoc signed.

**What you need:**

- [ ] **Apple Developer Program** membership, $99/year
      (<https://developer.apple.com/programs/>).
- [ ] A **"Developer ID Application"** certificate, exported as a `.p12`
      (Keychain Access → export → set a password).
- [ ] An **App Store Connect API key** for notarization (`.p8` file + Key ID +
      Issuer ID), preferred over an app-specific password.

**Add these GitHub repo secrets** (Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | `base64 -i DeveloperID.p12` |
| `P12_PASSWORD` | the password you set on the `.p12` |
| `APPLE_TEAM_ID` | your 10-char Team ID |
| `AC_API_KEY_ID` | App Store Connect API Key ID |
| `AC_API_ISSUER_ID` | App Store Connect Issuer ID |
| `AC_API_KEY_BASE64` | `base64 -i AuthKey_XXXX.p8` |

**Then in `release.yml`**, before packaging:

1. Import the cert with
   [`apple-actions/import-codesign-certs@v7`](https://github.com/Apple-Actions/import-codesign-certs).
2. Build with real signing: set `DEVELOPMENT_TEAM=$APPLE_TEAM_ID`,
   `CODE_SIGN_IDENTITY="Developer ID Application"`, `ENABLE_HARDENED_RUNTIME=YES`
   (replace the ad-hoc flags in `bin/release`).
3. Notarize + staple:
   ```bash
   xcrun notarytool submit dist/ZenTab-<v>.dmg \
     --key AuthKey.p8 --key-id "$AC_API_KEY_ID" --issuer "$AC_API_ISSUER_ID" --wait
   xcrun stapler staple dist/ZenTab-<v>.dmg
   ```

Once this is in place, delete the Gatekeeper note from the release body.

## 2. Decisions baked in as defaults (change if you disagree)

- [ ] **Bundle identifier** `org.nepjua.ZenTab`, change in `project.yml` (the source
      of truth) then run `bin/generate`.
- [ ] **Deployment target** macOS 15.0, raise to macOS 26 for newest-only APIs, or
      lower for wider reach (set in `project.yml` → `options.deploymentTarget`).
- [ ] **App Sandbox is OFF** by design (the switcher needs private SkyLight/CGS +
      Accessibility SPIs, which also rules out the Mac App Store). Hardened runtime
      stays on with `com.apple.security.cs.disable-library-validation` so the binary
      can load `SkyLight.framework`. See `ZenTab.entitlements`.

## 3. Nice-to-have polish

- [ ] **App icon**, there's no custom icon yet (the app uses the system default).
      Add a 1024×1024 image to `ZenTab/Assets.xcassets` as a new `AppIcon` set,
      then set it under target → General → App Icon.

## 4. Environment note (your machine)

Your shell exports `LD=ld`, which breaks raw `xcodebuild` linking from the
terminal (Xcode's GUI is fine; the `bin/*` scripts clear it). If you want raw
`xcodebuild` to work everywhere, consider scoping that export so it isn't global
in your `~/code/nepjua` shell config.
