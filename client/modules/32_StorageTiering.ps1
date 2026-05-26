#Requires -RunAsAdministrator
<# MODULE 32 - NVME DIRECTSTORAGE AND STORAGE TIERING #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "32" "NVME" "NVME DIRECTSTORAGE & STORAGE TIERING"

$physicalDisks = @(Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus, Size)
$volumes = @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" } | Select-Object DriveLetter, FileSystemLabel, FileSystem, HealthStatus, OperationalStatus, Size, SizeRemaining)
$bypass = New-Object System.Collections.Generic.List[object]

foreach ($volume in $volumes) {
    $root = "$($volume.DriveLetter):\"
    $state = & fsutil.exe bypassio state $root 2>&1
    $bypass.Add([PSCustomObject]@{
        drive = $volume.DriveLetter
        path = $root
        state = ($state -join "`n")
    }) | Out-Null
}

Write-Step "PHYSICAL DISKS"
Write-Host ""
foreach ($disk in $physicalDisks) {
    Write-Host ("  {0,-28} {1,-8} {2,-8} {3}" -f $disk.FriendlyName, $disk.MediaType, $disk.BusType, $disk.HealthStatus)
}

Write-Host ""
Write-Step "VOLUME AND BYPASSIO STATUS"
Write-Host ""
foreach ($volume in $volumes) {
    $freeGb = [math]::Round($volume.SizeRemaining / 1GB, 1)
    $sizeGb = [math]::Round($volume.Size / 1GB, 1)
    Write-Info ("{0}: {1} {2} free/{3} GB health={4}" -f $volume.DriveLetter, $volume.FileSystem, $freeGb, $sizeGb, $volume.HealthStatus)
}

$dir = Join-Path $Global:LogDir "storage"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$report = [PSCustomObject]@{
    captured_at = (Get-Date).ToString("o")
    physical_disks = $physicalDisks
    volumes = $volumes
    bypassio = $bypass
    storage_pools = @(Get-StoragePool | Select-Object FriendlyName, HealthStatus, OperationalStatus, IsPrimordial)
    virtual_disks = @(Get-VirtualDisk | Select-Object FriendlyName, HealthStatus, OperationalStatus, ResiliencySettingName, Size)
}
$path = Join-Path $dir ("storage-tiering_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
Write-OK "Storage tiering report: $path"

if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) {
    Write-Warn "Non-interactive mode: audit only."
    Wait-AnyKey
    return
}

Write-Host ""
Write-Host "  [1] Audit only"
Write-Host "  [2] Run ReTrim on fixed volumes"
Write-Host "  [3] Run TierOptimize on supported volumes"
Write-Host ""
$choice = Read-NeoChoice "  Pilihan [1-3]" @("1","2","3") "1"

if ($choice -eq "2" -and (Confirm-NeoAction "Run Optimize-Volume -ReTrim on fixed volumes?" $false)) {
    foreach ($volume in $volumes) {
        Optimize-Volume -DriveLetter $volume.DriveLetter -ReTrim -Verbose
    }
    Write-OK "ReTrim requested for fixed volumes."
}

if ($choice -eq "3" -and (Confirm-NeoAction "Run Optimize-Volume -TierOptimize on supported volumes?" $false)) {
    foreach ($volume in $volumes) {
        Optimize-Volume -DriveLetter $volume.DriveLetter -TierOptimize -Verbose
    }
    Write-OK "TierOptimize requested for fixed volumes."
}

Write-Footer
Wait-AnyKey
