# Code signing policy

How ZenTab's Windows binaries are signed, who can sign them, and what a user can verify.

This page is also the code signing policy that [SignPath Foundation](https://signpath.org/)
requires from the open-source projects it sponsors.

## Why signing matters here

ZenTab installs a low-level keyboard hook and replaces your system switcher. That is exactly
the shape of software you should be suspicious of, so every byte we ship should be traceable
to a build of this public repository, and Windows should be able to say who published it.

An unsigned download also gets a Microsoft Defender SmartScreen block, which trains people
to click through warnings. Signing is how we stop asking for that.

## The two channels are signed differently

ZenTab ships through two channels, and they use the two different mechanisms Windows offers.
Neither costs anything, which is the point: ZenTab is [free forever](../README.md), and a
paid certificate would be a permanent tax on that promise.

| Channel | Artifact | Signed by | SmartScreen |
| --- | --- | --- | --- |
| **Microsoft Store** | `.msix` | Microsoft, during certification | No warning, ever |
| **Direct download** (`cdn.nepjua.org`) | `.exe`, `.msi` | SignPath Foundation certificate, via SignPath.io | Warns until the file builds reputation |

**Store.** MSIX packages submitted to the Microsoft Store are re-signed by Microsoft with
its own certificate after certification. We deliberately submit the package **unsigned**:
a signed MSIX's `Publisher` must equal its certificate subject, and the Store requires the
publisher identity that Partner Center assigned. The package manifest lives in
[`windows/msix/AppxManifest.xml`](../windows/msix/AppxManifest.xml).

**Direct download.** The portable `.exe` and the `.msi` are Authenticode-signed with an
OV-level certificate provided free of charge by SignPath Foundation. The MSI is deep-signed:
the `ZenTab.exe` payload inside it is signed too, so the binary that ends up in
`Program Files` and runs every day carries the signature, not just the installer that
delivered it.

Be clear-eyed about what this buys: since 2024 no certificate grants instant SmartScreen
trust, not even Extended Validation. Reputation accrues per file as downloads accumulate, so
early releases still show a warning. The signature is what makes that reputation accrue at
all, and what lets you verify the publisher in the file's Properties dialog either way.

## Who can sign

ZenTab is a solo project, so the same person holds every role. Stating that plainly is more
useful than implying a review board that does not exist.

| Role | Who |
| --- | --- |
| Author | Yasin Uslu ([@yasinuslu](https://github.com/yasinuslu)) |
| Reviewer | Yasin Uslu |
| Approver | Yasin Uslu |

Contact: **nepjua@gmail.com**, or open an issue at
[github.com/yasinuslu/zentab/issues](https://github.com/yasinuslu/zentab/issues).

The signing certificate's private key is held in SignPath Foundation's HSM. It is never
downloaded, never present on a build machine, and never in this repository. Signing happens
only through SignPath's API, and only for artifacts produced by the workflow below.

## How a signed release is produced

1. A `windows-v*` tag is pushed to this repository.
2. [`.github/workflows/windows-release.yml`](../.github/workflows/windows-release.yml) builds
   the artifacts on a GitHub-hosted runner, from this repository's source, with no manual
   steps in between. SignPath Foundation requires GitHub-hosted runners for exactly this
   reason: the build is reproducible from public inputs.
3. The unsigned `.exe` and `.msi` are uploaded as a workflow artifact and submitted to
   SignPath, which independently verifies with GitHub which commit, workflow, and run
   produced them.
4. **A human approves the signing request.** Every request is approved by hand in the
   SignPath UI; nothing signs itself.
5. The signed binaries come back, the workflow refuses to continue if any of them returned
   unsigned, `SHA256SUMS.txt` is regenerated from the *signed* files, and everything is
   published to the CDN.

What gets signed is defined by
[`windows/signing/artifact-configuration.xml`](../windows/signing/artifact-configuration.xml),
committed here so that changes to it show up in review like any other change.

## Verifying a download

```powershell
# Who signed it, and is the signature intact?
Get-AuthenticodeSignature .\ZenTab-0.2.0-win-x64.msi | Format-List Status, SignerCertificate

# Does the file match the published checksum?
(Get-FileHash .\ZenTab-0.2.0-win-x64.msi -Algorithm SHA256).Hash.ToLower()
# compare against the matching line in SHA256SUMS.txt
```

`Status` should be `Valid`. Releases published before SignPath was in place are unsigned and
will report `NotSigned`.

## Reporting a problem

If you find a ZenTab binary that is signed but that you believe is malicious, tampered with,
or not built from this repository, report it to **nepjua@gmail.com** and to SignPath
Foundation at [signpath.org](https://signpath.org/). We will investigate any such report and
revoke if warranted.

## Privacy and data handling

**ZenTab itself collects nothing.** The Windows app contains no networking code at all: no
telemetry, no analytics, no update check, no crash reporting, no account. It reads window
titles, icons, and thumbnails from your running windows in order to draw the switcher, and
none of it leaves your machine. Its only persistent state is the optional config file you
write yourself (`%APPDATA%\zentab\config.toml`).

Signing and distribution involve third parties, each with its own privacy policy:

- [SignPath.io](https://signpath.io/privacy-policy) and
  [SignPath Foundation](https://signpath.org/privacy-policy) — code signing. Receives the
  build artifacts and the associated GitHub build metadata.
- [GitHub](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
  — source hosting and the build runners.
- [Cloudflare](https://www.cloudflare.com/privacypolicy/) — R2 object storage behind
  `cdn.nepjua.org`, which serves the direct downloads and therefore sees download requests.
- [Microsoft](https://privacy.microsoft.com/privacystatement) — the Microsoft Store channel
  and SmartScreen reputation checks.

## Attribution

Free code signing for ZenTab is provided by [SignPath Foundation](https://signpath.org/),
with the signing platform provided by [SignPath.io](https://signpath.io/). We are grateful
for both: they are the reason a free, solo, GPL-3.0 project can ship signed Windows binaries
at all.
