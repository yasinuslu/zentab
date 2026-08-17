#!/usr/bin/env pwsh
#requires -Version 7.0
# ZenTab build script — produces shippable artifacts in dist/.
#
#   ./build.ps1                  # the direct-download pair: portable exe + MSI installer
#   ./build.ps1 -Target portable # just the portable single-file exe
#   ./build.ps1 -Target installer# just the MSI
#   ./build.ps1 -Target msix     # just the Store package (needs the Windows SDK)
#   ./build.ps1 -Target release  # everything the release workflow ships
#   ./build.ps1 -Target checksums# re-hash dist/ without rebuilding (after signing)
#   ./build.ps1 -Version 0.2.0   # stamp a version into the exe, MSI, and filenames
#
# Artifacts (win-x64):
#   dist/ZenTab-<version>-win-x64-portable.exe  — truly portable: one self-contained
#       file, no .NET required, no zentab.toml beside it, so it uses the real
#       Alt+Tab / Alt+` / Ctrl+Alt+Tab gestures. Copy anywhere and double-click.
#   dist/ZenTab-<version>-win-x64.msi           — installs to Program Files, adds a
#       Start Menu shortcut, and starts at login.
#   dist/SHA256SUMS.txt                         — checksums for the two artifacts above,
#       which are the ones published to the CDN.
#   dist/ZenTab-<version>-win-x64.msix          — the Microsoft Store package. Deliberately
#       UNSIGNED: the Store re-signs it during certification, which is what makes a Store
#       install free of SmartScreen warnings. It is uploaded to Partner Center by hand, not
#       to the CDN, so it is not part of SHA256SUMS. See msix/AppxManifest.xml.
param(
    [string]$Version = "0.1.0",
    [ValidateSet("all", "portable", "installer", "msix", "release", "checksums")]
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"
# Make a non-zero exit from a native exe (dotnet, wix) abort the script.
$PSNativeCommandUseErrorActionPreference = $true
Set-Location $PSScriptRoot

# A version must be MSI-legal: 1–4 numeric fields, each 0–65535 (MSI compares the first 3).
if ($Version -notmatch '^\d{1,5}(\.\d{1,5}){0,3}$' -or
    (($Version -split '\.') | Where-Object { [int]$_ -gt 65535 })) {
    throw "Invalid -Version '$Version': use 1-4 dot-separated integers, each <= 65535 (e.g. 0.2.0)."
}

$rid        = "win-x64"
$publishDir = Join-Path $PSScriptRoot "bin\Release\net10.0-windows\$rid\publish"
$distDir    = Join-Path $PSScriptRoot "dist"
$iconFile   = Join-Path $PSScriptRoot "assets\zentab.ico"
$portable   = Join-Path $distDir "ZenTab-$Version-$rid-portable.exe"
$msi        = Join-Path $distDir "ZenTab-$Version-$rid.msi"
$msix       = Join-Path $distDir "ZenTab-$Version-$rid.msix"

# Which artifacts this run produces. The single-file publish feeds the first two; the MSIX
# needs its own loose-file publish, so it is tracked separately.
$wantPortable  = $Target -in @("all", "release", "portable")
$wantInstaller = $Target -in @("all", "release", "installer")
$wantMsix      = $Target -in @("release", "msix")

New-Item -ItemType Directory -Force $distDir | Out-Null

# 1. Publish the self-contained, single-file exe (shared by the portable exe and the MSI).
#    Clean first so a failed publish can never leave a stale exe to be packaged.
if ($wantPortable -or $wantInstaller) {
    Write-Host "==> Publishing self-contained single-file exe (v$Version)..." -ForegroundColor Cyan
    if (Test-Path $publishDir) { Remove-Item -Recurse -Force $publishDir }
    dotnet publish -c Release -r $rid -p:Version=$Version
    $builtExe = Join-Path $publishDir "ZenTab.exe"
    if (-not (Test-Path $builtExe)) { throw "Publish did not produce $builtExe" }
}

# 2. Portable artifact: the bare exe only. Shipping it without zentab.toml is what makes
#    it "truly portable" — Config.Load finds no toml, so dev mode is off and the real
#    Alt+Tab gestures are used.
if ($wantPortable) {
    # A just-built/previous exe can be briefly locked by an AV real-time scan; retry the copy.
    for ($attempt = 1; ; $attempt++) {
        try { Copy-Item $builtExe $portable -Force; break }
        catch {
            if ($attempt -ge 5) { throw }
            Write-Host "   (output locked, retrying $attempt/5...)" -ForegroundColor DarkYellow
            Start-Sleep -Seconds 2
        }
    }
    Write-Host "==> Portable exe: $portable" -ForegroundColor Green
}

# 3. Installer artifact: the WiX MSI (wraps the same self-contained exe).
if ($wantInstaller) {
    # Pinned to WiX v5: v6+ requires accepting the paid Open Source Maintenance Fee EULA.
    # Prefer the globally-installed pinned tool; fall back to PATH, then install.
    $wix = Join-Path $env:USERPROFILE ".dotnet\tools\wix.exe"
    if (-not (Test-Path $wix)) {
        $wix = (Get-Command wix -ErrorAction SilentlyContinue)?.Source
    }
    if (-not $wix -or -not (Test-Path $wix)) {
        Write-Host "==> Installing WiX dotnet tool (v5)..." -ForegroundColor Cyan
        dotnet tool install --global wix --version 5.0.2
        $wix = Join-Path $env:USERPROFILE ".dotnet\tools\wix.exe"
    }

    # Enforce the v5 pin even when wix came from PATH (v6 changes behavior / EULA).
    $wixVersion = (& $wix --version)
    if ($wixVersion -notmatch '^5\.') {
        throw "WiX $wixVersion found, but this project requires WiX v5 (v6+ needs the paid EULA). " +
              "Install it with: dotnet tool install --global wix --version 5.0.2"
    }

    Write-Host "==> Building MSI (WiX $wixVersion)..." -ForegroundColor Cyan
    & $wix build (Join-Path $PSScriptRoot "installer\ZenTab.wxs") `
        -d "PublishDir=$publishDir" -d "Version=$Version" -d "IconFile=$iconFile" `
        -pdbtype none -o $msi
    if (-not (Test-Path $msi)) { throw "WiX did not produce $msi" }
    Write-Host "==> Installer: $msi" -ForegroundColor Green
}

# 4. Store artifact: the MSIX package.
#
#    This is the free no-SmartScreen path — Microsoft re-signs the package during Store
#    certification — so the package we build here is intentionally left UNSIGNED. Signing it
#    ourselves would only conflict: a signed MSIX's Publisher must equal the certificate
#    subject, and the Store requires the Publisher that Partner Center assigned.
#
#    Two things differ from the other two artifacts:
#      - the publish is self-contained but NOT single-file. A single-file host would extract
#        itself to a temp directory on every cold start; inside a package the loose files are
#        already local and the extraction is pure cost.
#      - launch-at-login comes from the manifest's windows.startupTask extension rather than
#        the Run key (Startup.cs stands down when it sees a package identity).
if ($wantMsix) {
    # Windows SDK tools. Same directory for both; prefer the newest SDK installed.
    function Find-SdkTool([string]$exeName) {
        $roots = @("${env:ProgramFiles(x86)}\Windows Kits\10\bin", "$env:ProgramFiles\Windows Kits\10\bin")
        $found = $roots |
            Where-Object { Test-Path $_ } |
            ForEach-Object { Get-ChildItem $_ -Directory -ErrorAction SilentlyContinue } |
            Where-Object { $_.Name -match '^10\.\d+\.\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName "x64\$exeName" } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
        if (-not $found) { $found = (Get-Command $exeName -ErrorAction SilentlyContinue)?.Source }
        if (-not $found) {
            throw "$exeName not found. It ships with the Windows SDK — install the " +
                  "'Windows 10/11 SDK' component (or build with -Target all to skip the MSIX)."
        }
        return $found
    }
    $makeAppx = Find-SdkTool "makeappx.exe"
    $makePri  = Find-SdkTool "makepri.exe"

    $msixPublishDir = Join-Path $PSScriptRoot "bin\Release\net10.0-windows\$rid\publish-msix"
    $stageDir       = Join-Path $distDir "msix-stage"
    $priConfig      = Join-Path $distDir "priconfig.xml"

    Write-Host "==> Publishing self-contained loose-file build for MSIX (v$Version)..." -ForegroundColor Cyan
    if (Test-Path $msixPublishDir) { Remove-Item -Recurse -Force $msixPublishDir }
    dotnet publish -c Release -r $rid -p:Version=$Version -p:PublishSingleFile=false -o $msixPublishDir
    $msixExe = Join-Path $msixPublishDir "ZenTab.exe"
    if (-not (Test-Path $msixExe)) { throw "MSIX publish did not produce $msixExe" }

    # Stage: app payload + logo assets + a version-stamped copy of the manifest.
    if (Test-Path $stageDir) { Remove-Item -Recurse -Force $stageDir }
    New-Item -ItemType Directory -Force $stageDir | Out-Null
    Copy-Item "$msixPublishDir\*" $stageDir -Recurse -Force
    Copy-Item (Join-Path $PSScriptRoot "assets\msix") (Join-Path $stageDir "Assets") -Recurse -Force

    # An MSIX version is always four fields and the Store requires the fourth to be 0, so the
    # release version's first three fields are what actually carries the meaning.
    $vParts = @($Version -split '\.') + @('0', '0', '0')
    $msixVersion = "{0}.{1}.{2}.0" -f $vParts[0], $vParts[1], $vParts[2]

    $manifestSrc = Join-Path $PSScriptRoot "msix\AppxManifest.xml"
    [xml]$manifestXml = Get-Content $manifestSrc
    $manifestXml.Package.Identity.Version = $msixVersion
    $stagedManifest = Join-Path $stageDir "AppxManifest.xml"
    $manifestXml.Save($stagedManifest)

    if ($manifestXml.Package.Identity.Publisher -eq "CN=yasinuslu") {
        Write-Host "    NOTE: msix/AppxManifest.xml still has the placeholder Store identity." -ForegroundColor DarkYellow
        Write-Host "    This package sideloads fine but Partner Center will reject it." -ForegroundColor DarkYellow
        Write-Host "    See windows/docs/HUMAN-TODO.md." -ForegroundColor DarkYellow
    }

    # A resource index is what makes the target-based (unplated) 44x44 icon resolve — without
    # it the taskbar and Alt+Tab fall back to the plated tile logo.
    Write-Host "==> Indexing package resources (MakePri)..." -ForegroundColor Cyan
    & $makePri createconfig /cf $priConfig /dq en-US /o | Out-Null
    & $makePri new /pr $stageDir /cf $priConfig /of (Join-Path $stageDir "resources.pri") /o | Out-Null
    Remove-Item $priConfig -Force -ErrorAction SilentlyContinue

    Write-Host "==> Packing MSIX (v$msixVersion)..." -ForegroundColor Cyan
    & $makeAppx pack /d $stageDir /p $msix /o | Out-Null
    if (-not (Test-Path $msix)) { throw "MakeAppx did not produce $msix" }
    Remove-Item -Recurse -Force $stageDir
    Write-Host "==> Store package (unsigned, for Partner Center): $msix" -ForegroundColor Green
}

# 5. Checksums. Only the CDN-published artifacts belong here: the MSIX goes to Partner
#    Center by hand and is re-signed by Microsoft, so its hash would never match what a
#    user can download.
#
#    `-Target checksums` runs just this step. The release workflow needs it because signing
#    rewrites the binaries: the hashes published alongside a release have to be the hashes of
#    the signed files people actually download, not of the build output.
$sumsFile = Join-Path $distDir "SHA256SUMS.txt"
$signable = Get-ChildItem $distDir -Filter "ZenTab-$Version-*" | Where-Object { $_.Extension -in ".exe", ".msi" }
if (-not $signable -and $Target -eq "checksums") {
    throw "No dist/ZenTab-$Version-*.{exe,msi} to hash. Build them first, or check -Version."
}
if ($signable) {
    $signable | ForEach-Object {
        "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name
    } | Set-Content -Path $sumsFile -Encoding ascii
}

# 6. Summary.
$artifacts = Get-ChildItem $distDir -Filter "ZenTab-$Version-*" | Where-Object { $_.Extension -in ".exe", ".msi", ".msix" }
Write-Host ""
Write-Host "Done. Artifacts in dist/:" -ForegroundColor Cyan
$artifacts |
    Select-Object Name, @{N = "MB"; E = { [math]::Round($_.Length / 1MB, 1) } } |
    Format-Table -AutoSize | Out-Host
if ($signable) { Write-Host "Checksums: $sumsFile" -ForegroundColor Cyan }
