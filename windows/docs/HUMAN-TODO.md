# Human-only TODO — Windows

Things the automation can't do, each needing an account, an identity, or a human approval.
Nothing here blocks development or releases: the build produces all three artifacts today,
CI packs the Store package on every PR, and a `windows-v*` tag still cuts a full release —
just an unsigned one, with a loud warning in the log, until the accounts below exist.

Two independent tracks. Either one on its own is an improvement; together they cover both
ways people get ZenTab. Background and rationale: [`../../docs/code-signing-policy.md`](../../docs/code-signing-policy.md).

---

## Track 1 — Microsoft Store (the no-warning path)

This is the only free route where users see **no SmartScreen warning at all**, because
Microsoft re-signs the package itself. Everything on our side is built and waiting; what's
missing is the Partner Center identity.

- [ ] Create a free developer account at
      [storedeveloper.microsoft.com](https://storedeveloper.microsoft.com). Individual
      registration is free as of 2025/2026 (the old one-time $19 fee is gone) and open in
      ~200 countries.
- [ ] In [Partner Center](https://partner.microsoft.com/dashboard), reserve the app name
      **ZenTab**. If it's taken, pick the reserved name now, because it becomes part of the
      package identity below.
- [ ] Open **Product > Product identity** and copy the three assigned values into
      [`windows/msix/AppxManifest.xml`](../msix/AppxManifest.xml), replacing the three
      `STORE-TODO` placeholders:
      - `Package/Identity/@Name` ← *Package/Identity/Name*
      - `Package/Identity/@Publisher` ← *Package/Identity/Publisher* (a `CN=<GUID>`)
      - `Package/Properties/PublisherDisplayName` ← *Package/Identity/Publisher display name*

      They must match exactly or the submission is rejected. `build.ps1` warns while the
      placeholder publisher is still in place.
- [ ] Cut a release (or run the Windows Release workflow manually). Download the
      **`store-msix`** artifact from the run and upload that `.msix` in Partner Center.
      Submit it **unsigned** — do not sign it yourself; the Store signs it during
      certification, and a self-signed package will fail validation on the publisher
      mismatch.
- [ ] Fill in the Store listing: description, screenshots, the 300x300 Store logo, age
      rating, and privacy policy URL (point it at
      [`docs/code-signing-policy.md`](../../docs/code-signing-policy.md#privacy-and-data-handling),
      which states plainly that ZenTab collects nothing).
- [ ] **Expect a certification question about the keyboard hook.** ZenTab installs a
      low-level `WH_KEYBOARD_LL` hook and replaces the system switcher. That is legitimate
      for a `runFullTrust` packaged desktop app, but it is exactly what reviewers probe. If
      it comes up, the answer is: the hook only matches the three configured trigger chords,
      keystrokes are never recorded or transmitted, and the app contains no networking code
      at all.
- [ ] Once it's live, add the Store link to the download tables in
      [`README.md`](../../README.md) and [`windows/README.md`](../README.md), and to the
      website's download section.

## Track 2 — SignPath Foundation (signing the direct downloads)

Free OV-level Authenticode signing for the portable exe and the MSI, which is what people
who download from `cdn.nepjua.org` get. ZenTab qualifies: public repo, OSI-approved GPL-3.0
with no commercial dual-licensing, released, documented, actively maintained, and built
entirely on GitHub-hosted runners.

- [ ] Apply at [signpath.org/apply](https://signpath.org/apply). The application asks for the
      repository and the project's code signing policy — that policy is already written and
      published at [`docs/code-signing-policy.md`](../../docs/code-signing-policy.md).
- [ ] Enable multi-factor authentication on both the GitHub and SignPath accounts. This is a
      hard requirement of the Foundation's terms, not a suggestion.
- [ ] In SignPath, create the project, then paste
      [`windows/signing/artifact-configuration.xml`](../signing/artifact-configuration.xml)
      into **Artifact Configurations**.
- [ ] Add the GitHub repository **secret**:
      - `SIGNPATH_API_TOKEN`
- [ ] Add the GitHub repository **variables** (Settings > Secrets and variables > Actions >
      Variables). They aren't secret, and keeping them out of secrets means they show up in
      the log when something is misconfigured:
      - `SIGNPATH_ORGANIZATION_ID`
      - `SIGNPATH_PROJECT_SLUG`
      - `SIGNPATH_SIGNING_POLICY_SLUG`
      - `SIGNPATH_ARTIFACT_CONFIGURATION_SLUG`

      The release workflow checks all five and falls back to publishing unsigned, with a
      warning, if any is missing.
- [ ] **Cut one release and watch it.** Two things want a human eye the first time:
      - The job blocks on your approval in the SignPath UI (30 minute timeout), so be at a
        machine when you push the tag.
      - Confirm SignPath resolved the nested `ZenTab.exe` inside the MSI. If it reports that
        the nested path didn't match, the fix is to correct the `<pe-file path="...">` in
        the artifact configuration to the path the installer actually lays down.
- [ ] Verify a published download on a real machine:
      `Get-AuthenticodeSignature .\ZenTab-<v>-win-x64.msi` should say `Valid`, and installing
      it should leave a signed `ZenTab.exe` in `Program Files`.

---

## Not worth doing

- **Buying an EV certificate.** EV stopped granting instant SmartScreen trust in 2024; it
  now builds reputation exactly like OV, for $400+/year. There is no longer a reason to pay
  for it.
- **Azure Artifact Signing** (formerly Trusted Signing, ~$9.99/month). Good value and clean
  CI integration, but individual developers are limited to the USA and Canada, and
  organizations to the USA, Canada, EU, and UK. Worth revisiting only if that changes or if
  ZenTab ever ships under an entity in one of those regions.
- **Self-signing.** Worse than shipping unsigned: an untrusted certificate turns the
  SmartScreen warning into a hard block.
