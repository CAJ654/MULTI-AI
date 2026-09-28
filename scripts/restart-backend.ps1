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

# Pinned to 3.14, not bare `python`: the compiled extensions are built per
# interpreter, and only the 3.14 environment on this machine has the full
# chat-time dependency set (torch+CUDA, transformers, bitsandbytes, ...)
# installed. A bare `python` call resolves to whatever's first on PATH,
# which silently gives you a working-but-GPU-blind or non-importable server
# depending on what else happens to be installed there.
py -3.14 -c "from multi_ai.server import run; run()"
