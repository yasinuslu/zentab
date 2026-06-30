#!/usr/bin/env pwsh
#requires -Version 7.0
# Upload one file to the ZenTab R2 bucket and throw if it fails.
#
#   ./r2-publish.ps1 -File <local-file> -Key <remote-key> [-Mode rolling|immutable]
#
# R2 is addressed S3-style with SigV4, signed by curl.exe (no aws-cli needed).
# The endpoint already includes the bucket, so the object URL is just
# "$env:R2_API_URL/<remote-key>" (path-style). Required env (CI secrets):
#   R2_API_URL            e.g. https://<acct>.r2.cloudflarestorage.com/nepjua-cdn
#   R2_ACCESS_KEY_ID
#   R2_SECRET_ACCESS_KEY
#
# Mode: immutable = versioned artifacts (long cache); rolling = "latest"/"main"
# pointers we overwrite (always revalidate).
param(
    [Parameter(Mandatory)] [string]$File,
    [Parameter(Mandatory)] [string]$Key,
    [ValidateSet("rolling", "immutable")] [string]$Mode = "immutable"
)
$ErrorActionPreference = "Stop"

foreach ($v in "R2_API_URL", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY") {
    if (-not (Test-Path "env:$v")) { throw "$v is not set" }
}
if (-not (Test-Path $File)) { throw "r2-publish: no such file: $File" }

$cache = if ($Mode -eq "rolling") { "no-cache, max-age=0, must-revalidate" } else { "public, max-age=31536000, immutable" }
$ct = switch ([IO.Path]::GetExtension($File).ToLower()) {
    ".zip"  { "application/zip" }
    ".dmg"  { "application/x-apple-diskimage" }
    ".json" { "application/json" }
    ".txt"  { "text/plain; charset=utf-8" }
    default { "application/octet-stream" }   # .exe, .msi
}

$url = "$($env:R2_API_URL.TrimEnd('/'))/$($Key.TrimStart('/'))"
Write-Host "  -> $url  ($Mode, $ct)"

# `curl` is a PowerShell alias for Invoke-WebRequest, so call curl.exe explicitly.
# Credentials come from --user / SigV4; GitHub masks the secret values in logs.
& curl.exe --fail-with-body --silent --show-error --retry 3 --retry-all-errors `
    --aws-sigv4 "aws:amz:auto:s3" `
    --user "$($env:R2_ACCESS_KEY_ID):$($env:R2_SECRET_ACCESS_KEY)" `
    --header "Content-Type: $ct" `
    --header "Cache-Control: $cache" `
    --upload-file "$File" `
    "$url"
if ($LASTEXITCODE -ne 0) { throw "curl upload failed (exit $LASTEXITCODE) for $File" }

Write-Host "    uploaded $([IO.Path]::GetFileName($File))"
