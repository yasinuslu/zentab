#!/usr/bin/env pwsh
#requires -Version 7.0
# ZenTab build script — produces shippable artifacts in dist/.
#
#   ./build.ps1                  # both: portable exe + MSI installer
#   ./build.ps1 -Target portable # just the portable single-file exe
#   ./build.ps1 -Target installer# just the MSI
#   ./build.ps1 -Version 0.2.0   # stamp a version into the exe, MSI, and filenames
#
# Artifacts (win-x64):
#   dist/ZenTab-<version>-win-x64-portable.exe  — truly portable: one self-contained
#       file, no .NET required, no zentab.toml beside it, so it uses the real
#       Alt+Tab / Alt+` / Ctrl+Alt+Tab gestures. Copy anywhere and double-click.
#   dist/ZenTab-<version>-win-x64.msi           — installs to Program Files, adds a
#       Start Menu shortcut, and starts at login.
#   dist/SHA256SUMS.txt                         — checksums for the artifacts above.
param(
    [string]$Version = "0.1.0",
    [ValidateSet("all", "portable", "installer")]
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

New-Item -ItemType Directory -Force $distDir | Out-Null

# 1. Publish the self-contained, single-file exe (shared by both targets). Clean first so a
#    failed publish can never leave a stale exe to be packaged.
Write-Host "==> Publishing self-contained single-file exe (v$Version)..." -ForegroundColor Cyan
if (Test-Path $publishDir) { Remove-Item -Recurse -Force $publishDir }
dotnet publish -c Release -r $rid -p:Version=$Version
$builtExe = Join-Path $publishDir "ZenTab.exe"
if (-not (Test-Path $builtExe)) { throw "Publish did not produce $builtExe" }

# 2. Portable artifact: the bare exe only. Shipping it without zentab.toml is what makes
#    it "truly portable" — Config.Load finds no toml, so dev mode is off and the real
#    Alt+Tab gestures are used.
if ($Target -in @("all", "portable")) {
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
if ($Target -in @("all", "installer")) {
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

# 4. Checksums for whatever was produced this run.
$artifacts = Get-ChildItem $distDir -Filter "ZenTab-$Version-*" | Where-Object { $_.Extension -in ".exe", ".msi" }
$sumsFile = Join-Path $distDir "SHA256SUMS.txt"
$artifacts | ForEach-Object {
    "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name
} | Set-Content -Path $sumsFile -Encoding ascii

# 5. Summary.
Write-Host ""
Write-Host "Done. Artifacts in dist/:" -ForegroundColor Cyan
$artifacts |
    Select-Object Name, @{N = "MB"; E = { [math]::Round($_.Length / 1MB, 1) } } |
    Format-Table -AutoSize | Out-Host
Write-Host "Checksums: $sumsFile" -ForegroundColor Cyan
