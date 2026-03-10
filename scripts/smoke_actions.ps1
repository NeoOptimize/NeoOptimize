<#
  Smoke-test script for NeoOptimize smart actions (dry-run mode).
  - smart_booster: lists processes that would be lowered in priority or terminated
  - clear_temp_files: reports disk usage and shows candidate paths
  - health_check: runs SFC scan in verifyonly mode if available

  Run in PowerShell as a non-destructive test. Use Administrator for full checks.
#>

param(
  [switch]$DryRun = $true
)

Write-Host "NeoOptimize smoke actions (DryRun=$DryRun)"

function Show-SmartBoosterPlan {
  Write-Host "Smart Booster plan:"
  # Show top processes by memory
  Get-Process | Sort-Object -Property WS -Descending | Select-Object -First 10 Id,ProcessName,WS | Format-Table
  Write-Host "\nRecommendation: lower priority for non-essential processes (dry-run will not change anything)."
}

function Show-ClearTempPlan {
  Write-Host "Clear Temp plan:"
  $paths = @(
    "$env:TEMP",
    "$env:windir\Temp",
    "$env:LOCALAPPDATA\Temp"
  )
  foreach ($p in $paths) {
    if (Test-Path $p) {
      $size = (Get-ChildItem -Path $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
      $mb = [math]::Round($size / 1MB, 2)
      Write-Host "$p -> $mb MB"
    }
  }
  Write-Host "Dry-run: no files will be deleted.";
}

function Do-HealthCheck {
  Write-Host "Health check (SFC quick validation):"
  if ($DryRun) {
    Write-Host "(Dry-run) sfc scan skipped; run without -DryRun to perform full SFC."
    return
  }

  if (-not ([bool](Get-Command sfc -ErrorAction SilentlyContinue))) {
    Write-Host "sfc command not found on this system."
    return
  }

  Write-Host "Running 'sfc /verifyonly' (may take long)"
  sfc /verifyonly
}

Show-SmartBoosterPlan
Write-Host "\n"
Show-ClearTempPlan
Write-Host "\n"
Do-HealthCheck

Write-Host "Smoke actions completed. Review output and decide next steps."
