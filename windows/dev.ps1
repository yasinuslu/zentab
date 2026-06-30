#!/usr/bin/env pwsh
# Dev helper for ZenTab. Default action is a hot-reload watch loop.
param([string]$action = "watch")

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

switch ($action) {
    "watch" { dotnet watch run }
    "run"   { dotnet run }
    "build" { dotnet build }
    default { Write-Host "Usage: ./dev.ps1 [watch|run|build]" }
}
