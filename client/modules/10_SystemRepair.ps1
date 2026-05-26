#Requires -Version 5.1
<#
.SYNOPSIS
    NeoOptimize conservative Windows system repair wrapper.
.DESCRIPTION
    Runs SystemDiagnostics in Repair mode: WinRE enable, DISM RestoreHealth,
    SFC ScanNow, Windows Update reset, and critical service restart attempts.
#>

param([string]$ArgsJson = "")

$common = Join-Path $PSScriptRoot "..\lib\Common.ps1"
if (Test-Path $common) {
    . $common
    if (-not (Test-NeoHighRiskConsent -ActionName "System Repair" -RiskLevel "High" -Reason "Menjalankan DISM/SFC, reset Windows Update, WinRE, dan recovery service.")) {
        Wait-AnyKey
        exit 0
    }
}

$diagnostics = Join-Path $PSScriptRoot "16_SystemDiagnostics.ps1"
if (-not (Test-Path $diagnostics)) {
    Write-Host "[NeoOptimize] Missing diagnostics module: $diagnostics" -ForegroundColor Red
    exit 1
}

& $diagnostics -Mode Repair -ArgsJson $ArgsJson
exit $LASTEXITCODE
