<#
.SYNOPSIS
    Runs the Flutter app as a Windows desktop build.
.EXAMPLE
    .\scripts\run-windows.ps1
#>

$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..\app")
flutter run -d windows
