<#
.SYNOPSIS
    Runs the Flutter app as a Windows desktop build.
.DESCRIPTION
    The app depends on velopack_flutter (the in-app updater), whose native-assets
    build hook compiles a Rust crate — so `flutter run -d windows` needs rustup/cargo
    on PATH. rustup installs into %USERPROFILE%\.cargo\bin, but a terminal opened
    before the toolchain was installed inherits a stale PATH and can't see it, which
    surfaces as "Building native assets failed" (the hook fails to invoke
    `rustup show active-toolchain`). This script prepends that directory so the build
    works regardless of when the terminal was opened.
.EXAMPLE
    .\scripts\run-windows.ps1
#>

$ErrorActionPreference = "Stop"

# Ensure the Rust toolchain is on PATH for the velopack native-assets build hook.
$cargoBin = Join-Path $env:USERPROFILE ".cargo\bin"
if (Test-Path (Join-Path $cargoBin "rustup.exe")) {
    if (($env:Path -split ';') -notcontains $cargoBin) {
        $env:Path = "$cargoBin;$env:Path"
    }
} elseif (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
    Write-Warning "rustup/cargo not found. The velopack native-assets build hook needs Rust."
    Write-Warning "Install it once with:  winget install --id Rustlang.Rustup -e --source winget"
    Write-Warning "then rerun this script (it picks up %USERPROFILE%\.cargo\bin automatically)."
}

Set-Location (Join-Path $PSScriptRoot "..\app")
flutter run -d windows
