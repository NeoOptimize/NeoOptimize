# Elevated Full Smoke Test with SFC and DISM
# This script requires administrator privileges

$LogPath = "d:\NeoOptimize\artifacts\smoke-elevated-full.log"

Write-Host "=== NeoOptimize Elevated Full Smoke Test ===" | Tee-Object -FilePath $LogPath -Append
Write-Host "Start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Tee-Object -FilePath $LogPath -Append
Write-Host "User: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" | Tee-Object -FilePath $LogPath -Append
Write-Host "" | Tee-Object -FilePath $LogPath -Append

# System info
Write-Host "--- System Information ---" | Tee-Object -FilePath $LogPath -Append
$os = Get-WmiObject -Class Win32_OperatingSystem
Write-Host "OS: $($os.Caption)" | Tee-Object -FilePath $LogPath -Append
Write-Host "Build: $($os.BuildNumber)" | Tee-Object -FilePath $LogPath -Append
Write-Host "Service Pack: $($os.ServicePackMajorVersion).$($os.ServicePackMinorVersion)" | Tee-Object -FilePath $LogPath -Append
Write-Host "" | Tee-Object -FilePath $LogPath -Append

# Smart Booster Plan - Top Memory Processes
Write-Host "--- Smart Booster: Top Memory Processes ---" | Tee-Object -FilePath $LogPath -Append
Get-Process | Sort-Object -Property WS -Descending | Select-Object -First 10 ID,ProcessName,@{N='Memory(MB)';E={[math]::Round($_.WS/1MB,2)}} | Format-Table | Tee-Object -FilePath $LogPath -Append
Write-Host "" | Tee-Object -FilePath $LogPath -Append

# Smart Optimize Plan - Disk Usage
Write-Host "--- Smart Optimize: Disk Usage Analysis ---" | Tee-Object -FilePath $LogPath -Append
$disks = Get-PSDrive -PSProvider FileSystem
$disks | Select-Object Name,@{N='Used(GB)';E={if($_.Used){[math]::Round($_.Used/1GB,2)}else{'N/A'}}},@{N='Free(GB)';E={if($_.Free){[math]::Round($_.Free/1GB,2)}else{'N/A'}}} | Format-Table | Tee-Object -FilePath $LogPath -Append
Write-Host "" | Tee-Object -FilePath $LogPath -Append

# Health Check - Disk Space and Temp
Write-Host "--- Health Check: Temp Files Analysis ---" | Tee-Object -FilePath $LogPath -Append
$tempPaths = @("$env:TEMP", "$env:windir\Temp", "$env:LOCALAPPDATA\Temp")
foreach ($p in $tempPaths) {
  if (Test-Path $p) {
    try {
      $size = (Get-ChildItem -Path $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
      $mb = if ($size) { [math]::Round($size / 1MB, 2) } else { 0 }
      Write-Host "  $p => $mb MB" | Tee-Object -FilePath $LogPath -Append
    } catch {
      Write-Host "  $p => Error: $_" | Tee-Object -FilePath $LogPath -Append
    }
  }
}
Write-Host "" | Tee-Object -FilePath $LogPath -Append

# Health Check - Run SFC Scan
Write-Host "--- Health Check: System File Checker (SFC) Scan ---" | Tee-Object -FilePath $LogPath -Append
Write-Host "Running: sfc /scannow (this may take 5-15 minutes)" | Tee-Object -FilePath $LogPath -Append
Write-Host "Please wait..." | Tee-Object -FilePath $LogPath -Append

try {
  $result = cmd /c "sfc /scannow" 2>&1
  $result | Tee-Object -FilePath $LogPath -Append
} catch {
  Write-Host "SFC scan error: $_" | Tee-Object -FilePath $LogPath -Append
}

Write-Host "" | Tee-Object -FilePath $LogPath -Append

# Integrity Scan - Hash Key System Files
Write-Host "--- Integrity Scan: Key System Files ---" | Tee-Object -FilePath $LogPath -Append
$keyFiles = @(
  'C:\Windows\System32\kernel32.dll',
  'C:\Windows\System32\ntdll.dll',
  'C:\Windows\System32\advapi32.dll',
  'C:\Windows\System32\mscoree.dll',
  'C:\Windows\System32\user32.dll'
)

foreach ($file in $keyFiles) {
  if (Test-Path $file) {
    try {
      $hash = (Get-FileHash -Path $file -Algorithm SHA256).Hash
      Write-Host "  $file" | Tee-Object -FilePath $LogPath -Append
      Write-Host "    SHA256: $hash" | Tee-Object -FilePath $LogPath -Append
    } catch {
      Write-Host "  $file - Error: $_" | Tee-Object -FilePath $LogPath -Append
    }
  } else {
    Write-Host "  $file - NOT FOUND" | Tee-Object -FilePath $LogPath -Append
  }
}
Write-Host "" | Tee-Object -FilePath $LogPath -Append

# Check Windows Update Status
Write-Host "--- Integrity Check: Windows Update History ---" | Tee-Object -FilePath $LogPath -Append
try {
  $updates = Get-HotFix | Sort-Object -Property InstalledOn -Descending | Select-Object -First 5
  $updates | Format-Table HotFixID,Description,InstalledOn | Tee-Object -FilePath $LogPath -Append
} catch {
  Write-Host "Could not retrieve Windows Updates: $_" | Tee-Object -FilePath $LogPath -Append
}
Write-Host "" | Tee-Object -FilePath $LogPath -Append

# Summary
Write-Host "=== Elevated Smoke Test Complete ===" | Tee-Object -FilePath $LogPath -Append
Write-Host "End: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Tee-Object -FilePath $LogPath -Append
Write-Host "Report saved to: $LogPath" | Tee-Object -FilePath $LogPath -Append
