#Requires -RunAsAdministrator
<# MODULE 21 - EVENT LOG MAINTENANCE #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "21" "LOG" "EVENT LOG MAINTENANCE"

$logs = @(
    "Application",
    "System",
    "Setup",
    "Microsoft-Windows-WindowsUpdateClient/Operational",
    "Microsoft-Windows-Diagnostics-Performance/Operational"
)

$dir = Join-Path $Global:LogDir "eventlogs"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }

Write-Step "EVENT LOG STATUS"
Write-Host ""
foreach ($log in $logs) {
    $info = & wevtutil.exe gli $log 2>&1
    $enabled = ($info | Select-String "enabled:")
    $records = ($info | Select-String "numberOfLogRecords:")
    Write-Info ("{0}: {1}; {2}" -f $log, $enabled, $records)
}

Write-Host ""
Write-Step "EXPORT LOGS"
Write-Host ""
foreach ($log in $logs) {
    $safe = ($log -replace '[\\/:*?"<>|]+', '_')
    $out = Join-Path $dir ("{0}_{1}.evtx" -f $safe, (Get-Date -Format "yyyyMMdd_HHmmss"))
    & wevtutil.exe epl $log $out 2>&1 | Out-Null
    if (Test-Path $out) { Write-OK "Exported: $out" } else { Write-Warn "Export failed: $log" }
}

if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) {
    Write-Warn "Non-interactive mode: export only, no log clearing."
    Wait-AnyKey
    return
}

Write-Host ""
Write-Host "  [1] Export only"
Write-Host "  [2] Clear Application/System/Setup after export"
Write-Host ""
$choice = Read-NeoChoice "  Pilihan [1-2]" @("1","2") "1"
if ($choice -eq "2" -and (Confirm-NeoAction "Clear Application, System, and Setup event logs after export?" $false)) {
    foreach ($log in @("Application", "System", "Setup")) {
        & wevtutil.exe cl $log 2>&1 | Out-Null
        Write-OK "Cleared: $log"
    }
}

Write-Host ""
Write-Separator "=" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)EVENT LOG MAINTENANCE SELESAI$($Global:RESET)"
Write-Footer
Wait-AnyKey
