# Human-only TODO

Things the automation can't do for you — each needs an account, a secret, or a
personal decision. Nothing here blocks day-to-day development; the app builds,
runs, tests, and produces (unsigned) releases as-is.

## 1. Signed + notarized releases (optional, recommended before public distribution)

Today `release.yml` ships an **ad-hoc-signed, un-notarized** `.dmg`. It runs, but
macOS Gatekeeper warns users on first launch (and on macOS 15+ they must go to
**System Settings → Privacy & Security → Open Anyway**). To remove that friction
you need an Apple Developer account and a few CI secrets.

**What you need:**

- [ ] **Apple Developer Program** membership — $99/year
      (<https://developer.apple.com/programs/>).
- [ ] A **"Developer ID Application"** certificate, exported as a `.p12`
      (Keychain Access → export → set a password).
- [ ] An **App Store Connect API key** for notarization (`.p8` file + Key ID +
      Issuer ID) — preferred over an app-specific password.

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

- [ ] **Bundle identifier** `org.nepjua.ZenTab` — change in Xcode (target →
      Signing & Capabilities) and in `project.yml` if you regenerate.
- [ ] **Deployment target** macOS 15.0 — raise to macOS 26 for newest-only APIs,
      or lower for wider reach (Xcode → target → General → Minimum Deployments).
- [ ] **App Sandbox** is enabled. Add entitlements in `ZenTab.entitlements` when a
      feature needs broader access.

## 3. Nice-to-have polish

- [ ] **App icon** — there's no custom icon yet (the app uses the system default).
      Add a 1024×1024 image to `ZenTab/Assets.xcassets` as a new `AppIcon` set,
      then set it under target → General → App Icon.

## 4. Environment note (your machine)

Your shell exports `LD=ld`, which breaks raw `xcodebuild` linking from the
terminal (Xcode's GUI is fine; the `bin/*` scripts clear it). If you want raw
`xcodebuild` to work everywhere, consider scoping that export so it isn't global
in your `~/code/nepjua` shell config.
