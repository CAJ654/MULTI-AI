<#
.SYNOPSIS
    Runs the Flutter app as a web build in a browser.
.DESCRIPTION
    Launches app/ on the web target (app/web/) with `flutter run -d edge` by default.
    Pass -Device chrome (or any web id from `flutter devices`) to use another browser.
    The web build talks to the Python backend over HTTP, so start the backend first
    (see scripts/restart-backend.ps1) if you want model lists and chat to work.
.PARAMETER Device
    Flutter device id for the browser. Defaults to edge.
.PARAMETER Port
    Port for the dev server. Defaults to 8080 so it doesn't collide with the backend on 8000.
.EXAMPLE
    .\scripts\run-web.ps1
.EXAMPLE
    .\scripts\run-web.ps1 -Device chrome -Port 9000
#>
param(
    [string]$Device = "edge",
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "flutter was not found on PATH. Install Flutter or add its bin directory to PATH."
    exit 1
}

Set-Location (Join-Path $PSScriptRoot "..\app")
flutter run -d $Device --web-port $Port
