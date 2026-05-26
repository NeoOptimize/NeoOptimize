#Requires -Version 5.1
<#
.SYNOPSIS
    NeoOptimize conservative Windows system repair wrapper.
.DESCRIPTION
    Runs SystemDiagnostics in Repair mode: WinRE enable, DISM RestoreHealth,
    SFC ScanNow, Windows Update reset, and critical service restart attempts.
#>

param([string]$ArgsJson = "")

$diagnostics = Join-Path $PSScriptRoot "16_SystemDiagnostics.ps1"
if (-not (Test-Path $diagnostics)) {
    Write-Host "[NeoOptimize] Missing diagnostics module: $diagnostics" -ForegroundColor Red
    exit 1
}

& $diagnostics -Mode Repair -ArgsJson $ArgsJson
exit $LASTEXITCODE
