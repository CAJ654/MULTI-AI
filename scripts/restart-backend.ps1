<#
.SYNOPSIS
    Stops whatever is listening on the backend port (if anything) and restarts multi-ai-server.
.EXAMPLE
    .\scripts\restart-backend.ps1
#>
param(
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"

$conns = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
if ($conns) {
    $processIds = $conns | Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($processId in $processIds) {
        Write-Host "Stopping process $processId listening on port $Port..."
        Stop-Process -Id $processId -Force
    }
    Start-Sleep -Seconds 1
} else {
    Write-Host "No process currently listening on port $Port."
}

Write-Host "Starting backend (multi-ai-server)..."
Set-Location (Join-Path $PSScriptRoot "..\Multi-AI")
python -c "from multi_ai.server import run; run()"
