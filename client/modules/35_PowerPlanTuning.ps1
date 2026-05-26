#Requires -RunAsAdministrator
<# MODULE 35 - POWER PLAN TUNING #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "35" "PWR" "POWER PLAN TUNING"

$schemes = & powercfg.exe /list 2>&1
$active = & powercfg.exe /getactivescheme 2>&1
$requests = & powercfg.exe /requests 2>&1
$sleepStates = & powercfg.exe /a 2>&1

Write-Step "POWER PLAN STATUS"
Write-Host ""
$active | ForEach-Object { Write-Info $_ }
Write-Host ""
Write-Step "POWER REQUESTS"
Write-Host ""
$requests | ForEach-Object { Write-Host "  $_" }

$dir = Join-Path $Global:LogDir "power"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$report = [PSCustomObject]@{
    captured_at = (Get-Date).ToString("o")
    schemes = $schemes
    active = $active
    requests = $requests
    sleep_states = $sleepStates
}
$path = Join-Path $dir ("power-plan_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$report | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding UTF8
Write-OK "Power plan report: $path"

if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) {
    Write-Warn "Non-interactive mode: audit only."
    Wait-AnyKey
    return
}

Write-Host ""
Write-Host "  [1] Audit only"
Write-Host "  [2] Activate Balanced"
Write-Host "  [3] Activate High Performance"
Write-Host "  [4] Create/activate Ultimate Performance"
Write-Host "  [5] Generate powercfg /energy report"
Write-Host ""
$choice = Read-NeoChoice "  Pilihan [1-5]" @("1","2","3","4","5") "1"

if ($choice -eq "2" -and (Confirm-NeoAction "Activate Balanced power scheme?" $false)) {
    & powercfg.exe /setactive SCHEME_BALANCED
    Write-OK "Balanced power scheme activated."
}

if ($choice -eq "3" -and (Confirm-NeoAction "Activate High Performance power scheme?" $false)) {
    & powercfg.exe /setactive SCHEME_MIN
    Write-OK "High Performance power scheme activated."
}

if ($choice -eq "4" -and (Confirm-NeoAction "Create and activate Ultimate Performance power scheme?" $false)) {
    $ultimate = "e9a42b02-d5df-448d-aa00-03f14749eb61"
    $dup = & powercfg.exe /duplicatescheme $ultimate 2>&1
    $guid = $ultimate
    if (($dup -join " ") -match '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})') {
        $guid = $Matches[1]
    }
    & powercfg.exe /setactive $guid
    Write-OK "Ultimate Performance power scheme activated: $guid"
}

if ($choice -eq "5" -and (Confirm-NeoAction "Run powercfg /energy for 60 seconds?" $false)) {
    $energyPath = Join-Path $dir ("power-energy_{0}.html" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    & powercfg.exe /energy /duration 60 /output $energyPath
    Write-OK "Energy report: $energyPath"
}

Write-Footer
Wait-AnyKey
