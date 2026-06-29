#!/usr/bin/env pwsh
# Builds a release ZenTab.exe (self-contained, single file) and an MSI installer.
# Output: dist/ZenTab-<version>-win-x64.msi
param([string]$Version = "0.1.0")

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$rid = "win-x64"
$publishDir = Join-Path $PSScriptRoot "bin\Release\net10.0-windows\$rid\publish"
$distDir = Join-Path $PSScriptRoot "dist"
$msi = Join-Path $distDir "ZenTab-$Version-$rid.msi"

Write-Host "==> Publishing self-contained single-file exe..." -ForegroundColor Cyan
dotnet publish -c Release -r $rid -p:Version=$Version

# Resolve the WiX dotnet tool (install globally if missing).
# Pinned to v5: WiX v6+ requires accepting the paid Open Source Maintenance Fee EULA.
$wix = Join-Path $env:USERPROFILE ".dotnet\tools\wix.exe"
if (-not (Test-Path $wix)) {
    $wix = (Get-Command wix -ErrorAction SilentlyContinue)?.Source
}
if (-not $wix -or -not (Test-Path $wix)) {
    Write-Host "==> Installing WiX dotnet tool (v5)..." -ForegroundColor Cyan
    dotnet tool install --global wix --version 5.0.2 | Out-Host
    $wix = Join-Path $env:USERPROFILE ".dotnet\tools\wix.exe"
}

New-Item -ItemType Directory -Force $distDir | Out-Null

Write-Host "==> Building MSI..." -ForegroundColor Cyan
& $wix build (Join-Path $PSScriptRoot "installer\ZenTab.wxs") -d "PublishDir=$publishDir" -o $msi

Write-Host "==> Done: $msi" -ForegroundColor Green
