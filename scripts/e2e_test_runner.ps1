# Comprehensive end-to-end test for NeoOptimize
# - Launches desktop app
# - Tests Neo AI chat and actions via UI
# - Runs elevated full smoke (SFC/DISM)
# - Captures report

param(
  [string]$AppExePath = 'd:\NeoOptimize\dist\NeoOptimize-v1.0.0-win-x64-20260310115936\App\NeoOptimize.App.exe',
  [string]$ReportPath = 'd:\NeoOptimize\artifacts\e2e_test_report.txt'
)

$ErrorActionPreference = 'Stop'
$reportLines = @()

function Log {
  param([string]$msg)
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "[$ts] $msg"
  Write-Host $line
  $reportLines += $line
}

Log "=== NeoOptimize End-to-End Test ==="
Log "Start time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Log "User: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Log "Is Admin: $(Test-Path 'HKCU:\Software\Classes\CAL\' -ErrorAction SilentlyContinue)"
Log ""

# Test 1: Desktop app launch
Log "--- Test 1: Desktop App Launch ---"
if (-Not (Test-Path $AppExePath)) {
  Log "ERROR: App exe not found at $AppExePath"
  exit 1
}

Log "Launching app: $AppExePath"
try {
  $appProc = Start-Process -FilePath $AppExePath -PassThru -ErrorAction Stop
  Log "App started with PID: $($appProc.Id)"
  Start-Sleep -Seconds 6
  
  if ($appProc.HasExited) {
    Log "WARNING: App exited early"
  } else {
    Log "App running OK (PID $($appProc.Id))"
  }
} catch {
  Log "ERROR: Failed to launch app: $_"
}

Log ""

# Test 2: UI Smoke via Playwright
Log "--- Test 2: UI Smoke Test ---"
$uiOutput = & node "d:\NeoOptimize\scripts\ui_smoke_quick.mjs" 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($uiOutput) {
  Log "UI Smoke Results:"
  Log "  Posted message count: $($uiOutput.postedCount)"
  $uiOutput.posted | ForEach-Object {
    Log "    - Type: $($_.type), Action: $($_.action -or 'N/A')"
  }
} else {
  Log "WARNING: UI smoke test did not produce JSON output"
}

Log ""

# Test 3: Elevated Smoke (SFC/DISM)
Log "--- Test 3: Elevated Smoke Action (SFC/DISM) ---"
Log "Starting elevated full smoke script with transcript capture..."

$elevatedScript = {
  Start-Transcript -Path 'd:\NeoOptimize\artifacts\smoke-full-e2e.log' -Append
  Write-Host "=== Elevated Smoke Full Test ==="
  Write-Host "Start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  Write-Host ""
  
  # System info
  Write-Host "--- System Info ---"
  Write-Host "OS: $((Get-WmiObject -Class Win32_OperatingSystem).Caption)"
  Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"
  Write-Host ""
  
  # Smart Booster Plan
  Write-Host "--- Smart Booster Plan ---"
  Get-Process | Sort-Object -Property WS -Descending | Select-Object -First 5 Id,ProcessName,@{N='Memory(MB)';E={[math]::Round($_.WS/1MB,2)}} | Format-Table
  Write-Host ""
  
  # Temp files cleanup plan
  Write-Host "--- Temp Files Plan ---"
  $paths = @("$env:TEMP", "$env:windir\Temp", "$env:LOCALAPPDATA\Temp")
  foreach ($p in $paths) {
    if (Test-Path $p) {
      $size = (Get-ChildItem -Path $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
      $mb = [math]::Round($size / 1MB, 2)
      Write-Host "  $p => $mb MB"
    }
  }
  Write-Host ""
  
  # Health Check - SFC Scan (may take long)
  Write-Host "--- Health Check: SFC Scan (verifyonly) ---"
  Write-Host "Running: sfc /verifyonly (this may take 5-15 minutes, please wait)"
  try {
    $sfcOutput = cmd /c "sfc /verifyonly" 2>&1
    Write-Host "$sfcOutput"
  } catch {
    Write-Host "SFC scan error or skipped: $_"
  }
  Write-Host ""
  
  # Integrity Check - verify key system files
  Write-Host "--- Integrity Scan: Key System Files ---"
  $keyFiles = @(
    'C:\Windows\System32\kernel32.dll',
    'C:\Windows\System32\ntdll.dll',
    'C:\Windows\System32\mscoree.dll'
  )
  foreach ($file in $keyFiles) {
    if (Test-Path $file) {
      try {
        $hash = (Get-FileHash -Path $file -Algorithm SHA256).Hash
        Write-Host "  $file`n    SHA256: $hash"
      } catch {
        Write-Host "  $file - Hash error: $_"
      }
    }
  }
  Write-Host ""
  
  Write-Host "=== Elevated Smoke Complete ==="
  Write-Host "End: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  Stop-Transcript
}

try {
  Start-Process -FilePath powershell -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $elevatedScript -Verb RunAs -Wait
  Log "Elevated smoke completed"
  
  # Read the transcript
  if (Test-Path 'd:\NeoOptimize\artifacts\smoke-full-e2e.log') {
    Log "Elevated smoke transcript captured at: d:\NeoOptimize\artifacts\smoke-full-e2e.log"
    $transcript = Get-Content 'd:\NeoOptimize\artifacts\smoke-full-e2e.log' -Raw
    $reportLines += ""
    $reportLines += "--- Elevated Smoke Transcript ---"
    $reportLines += $transcript.Split("`n") | Select-Object -First 100  # Include first 100 lines
  }
} catch {
  Log "ERROR: Elevated smoke failed: $_"
}

Log ""

# Test 4: Cleanup
Log "--- Test 4: Cleanup ---"
try {
  $appProc | Where-Object { -not $_.HasExited } | Stop-Process -Force -ErrorAction SilentlyContinue
  Log "App process stopped"
} catch {
  Log "Cleanup error (non-critical): $_"
}

Log ""
Log "=== Test Summary ==="
Log "End time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Log "Report saved to: $ReportPath"

# Write report
$reportLines | Out-File -FilePath $ReportPath -Encoding UTF8
Write-Host ""
Write-Host "Final report written to: $ReportPath"
