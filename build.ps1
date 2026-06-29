#!/usr/bin/env pwsh
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
param(
    [string]$Version = "0.1.0",
    [ValidateSet("all", "portable", "installer")]
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$rid        = "win-x64"
$publishDir = Join-Path $PSScriptRoot "bin\Release\net10.0-windows\$rid\publish"
$distDir    = Join-Path $PSScriptRoot "dist"
$portable   = Join-Path $distDir "ZenTab-$Version-$rid-portable.exe"
$msi        = Join-Path $distDir "ZenTab-$Version-$rid.msi"

New-Item -ItemType Directory -Force $distDir | Out-Null

# 1. Publish the self-contained, single-file exe (shared by both targets).
Write-Host "==> Publishing self-contained single-file exe (v$Version)..." -ForegroundColor Cyan
dotnet publish -c Release -r $rid -p:Version=$Version
$builtExe = Join-Path $publishDir "ZenTab.exe"
if (-not (Test-Path $builtExe)) { throw "Publish did not produce $builtExe" }

# 2. Portable artifact: the bare exe only. Shipping it without zentab.toml is what makes
#    it "truly portable" — Config.Load finds no toml, so dev mode is off and the real
#    Alt+Tab gestures are used.
if ($Target -in @("all", "portable")) {
    Copy-Item $builtExe $portable -Force
    Write-Host "==> Portable exe: $portable" -ForegroundColor Green
}

# 3. Installer artifact: the WiX MSI (wraps the same self-contained exe).
if ($Target -in @("all", "installer")) {
    # Pinned to WiX v5: v6+ requires accepting the paid Open Source Maintenance Fee EULA.
    $wix = Join-Path $env:USERPROFILE ".dotnet\tools\wix.exe"
    if (-not (Test-Path $wix)) {
        $wix = (Get-Command wix -ErrorAction SilentlyContinue)?.Source
    }
    if (-not $wix -or -not (Test-Path $wix)) {
        Write-Host "==> Installing WiX dotnet tool (v5)..." -ForegroundColor Cyan
        dotnet tool install --global wix --version 5.0.2 | Out-Host
        $wix = Join-Path $env:USERPROFILE ".dotnet\tools\wix.exe"
    }

    Write-Host "==> Building MSI..." -ForegroundColor Cyan
    & $wix build (Join-Path $PSScriptRoot "installer\ZenTab.wxs") `
        -d "PublishDir=$publishDir" -d "Version=$Version" -pdbtype none -o $msi
    Write-Host "==> Installer: $msi" -ForegroundColor Green
}

# 4. Summary.
Write-Host ""
Write-Host "Done. Artifacts in dist/:" -ForegroundColor Cyan
Get-ChildItem $distDir -Filter "ZenTab-$Version-*" |
    Select-Object Name, @{N = "MB"; E = { [math]::Round($_.Length / 1MB, 1) } } |
    Format-Table -AutoSize | Out-Host
