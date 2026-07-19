<#
.SYNOPSIS
    Boots the Pixel_9 emulator and launches the Flutter app on it once it's ready.
.EXAMPLE
    .\scripts\run-app.ps1
.EXAMPLE
    .\scripts\run-app.ps1 -Emulator Pixel_9 -Device emulator-5554
#>
param(
    [string]$Emulator = "Pixel_9",
    [string]$Device = "emulator-5554",
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"

Write-Host "Launching emulator '$Emulator' (first boot can take ~60s)..."
flutter emulators --launch $Emulator

Write-Host "Waiting for '$Device' to appear in 'flutter devices'..."
$elapsed = 0
$pollSeconds = 3
$ready = $false

while ($elapsed -lt $TimeoutSeconds) {
    $devices = flutter devices 2>$null
    if ($devices -match [regex]::Escape($Device)) {
        $ready = $true
        break
    }
    Start-Sleep -Seconds $pollSeconds
    $elapsed += $pollSeconds
}

if (-not $ready) {
    Write-Error "Timed out after ${TimeoutSeconds}s waiting for $Device to come online."
    exit 1
}

Write-Host "$Device is online. Starting app..."
Set-Location (Join-Path $PSScriptRoot "..\app")
flutter run -d $Device
