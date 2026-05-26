#Requires -Version 5.1
#Requires -RunAsAdministrator
<# MODULE 09  MAINTENANCE, CLEANUP SCHEDULER, DISK MANAGER #>

param(
    [ValidateSet("Menu", "CleanAll", "ScheduleClean", "SmartBooster", "SmartOptimize", "DeepScan", "SystemDiagnostics", "SystemRepair", "DiskStatus", "DiskScan", "DiskRepair", "DiskOptimize", "HealthRepair", "Full")]
    [string]$Mode = "Menu"
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

$Script:Root = Split-Path -Parent $PSScriptRoot
$Script:TaskName = "NeoOptimize Smart Cleanup"
$Script:MaintenanceReportDir = Join-Path $Script:Root "reports\maintenance"
if (-not (Test-Path $Script:MaintenanceReportDir)) {
    New-Item -Path $Script:MaintenanceReportDir -ItemType Directory -Force | Out-Null
}

function Remove-NeoPathContents {
    param(
        [string]$Path,
        [string]$Label,
        [switch]$KeepRoot
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        Write-Skip "$Label"
        return 0
    }

    $before = Get-FolderSizeMB $Path
    try {
        if ($KeepRoot) {
            Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -Path $Path -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {}
    $after = Get-FolderSizeMB $Path
    $freed = [math]::Round([math]::Max(0, $before - $after), 2)
    if ($freed -gt 0) {
        Write-OK "$Label freed ${freed} MB"
    } else {
        Write-Skip "$Label already clean"
    }
    return $freed
}

function Invoke-CleanAllJunk {
    Write-ModuleHeader "09" "" "CLEAN ALL JUNK"
    Write-Info "Cleaning temp, prefetch, Defender cache, update cache, browser cache, thumbnails, shader cache."
    Write-Host ""

    $freedTotal = 0.0
    $paths = @(
        @{ P = $env:TEMP; L = "User Temp"; Keep = $true },
        @{ P = $env:TMP; L = "User TMP"; Keep = $true },
        @{ P = "$env:LOCALAPPDATA\Temp"; L = "LocalAppData Temp"; Keep = $true },
        @{ P = "C:\Windows\Temp"; L = "Windows Temp"; Keep = $true },
        @{ P = "C:\Windows\Prefetch"; L = "Windows Prefetch"; Keep = $true },
        @{ P = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"; L = "Internet Cache"; Keep = $true },
        @{ P = "$env:LOCALAPPDATA\Microsoft\Windows\WebCache"; L = "Windows WebCache"; Keep = $true },
        @{ P = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; L = "Explorer thumbnail/icon cache"; Keep = $true },
        @{ P = "$env:LOCALAPPDATA\D3DSCache"; L = "DirectX shader cache"; Keep = $true },
        @{ P = "$env:LOCALAPPDATA\NVIDIA\DXCache"; L = "NVIDIA DX cache"; Keep = $true },
        @{ P = "$env:LOCALAPPDATA\NVIDIA\GLCache"; L = "NVIDIA GL cache"; Keep = $true },
        @{ P = "$env:LOCALAPPDATA\AMD\DxCache"; L = "AMD DX cache"; Keep = $true },
        @{ P = "$env:LOCALAPPDATA\CrashDumps"; L = "Crash dumps"; Keep = $true },
        @{ P = "C:\Windows\Minidump"; L = "Minidump files"; Keep = $true },
        @{ P = "C:\ProgramData\Microsoft\Windows\WER\ReportArchive"; L = "WER archive"; Keep = $true },
        @{ P = "C:\ProgramData\Microsoft\Windows\WER\ReportQueue"; L = "WER queue"; Keep = $true },
        @{ P = "C:\ProgramData\Microsoft\Windows\WER\Temp"; L = "WER temp"; Keep = $true },
        @{ P = "C:\ProgramData\Microsoft\Windows Defender\Scans\History\Service"; L = "Windows Defender scan history cache"; Keep = $true },
        @{ P = "C:\ProgramData\Microsoft\Windows Defender\Scans\History\CacheManager"; L = "Windows Defender cache manager"; Keep = $true }
    )

    Write-Step "JUNK PATHS"
    foreach ($item in $paths) {
        $freedTotal += Remove-NeoPathContents -Path $item.P -Label $item.L -KeepRoot:([bool]$item.Keep)
    }

    Write-Host ""
    Write-Step "BROWSER CACHE"
    $browserPaths = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Opera Software\Opera Stable\Cache"
    )
    foreach ($path in $browserPaths) {
        $freedTotal += Remove-NeoPathContents -Path $path -Label (Split-Path $path -Leaf) -KeepRoot
    }

    $ffProfiles = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $ffProfiles) {
        Get-ChildItem -Path $ffProfiles -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            foreach ($cacheName in @("cache2", "startupCache", "thumbnails", "OfflineCache")) {
                $freedTotal += Remove-NeoPathContents -Path (Join-Path $_.FullName $cacheName) -Label "Firefox $cacheName" -KeepRoot
            }
        }
    }

    Write-Host ""
    Write-Step "WINDOWS UPDATE AND DELIVERY CACHE"
    $services = @("wuauserv", "bits", "dosvc")
    foreach ($svc in $services) { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue }
    $freedTotal += Remove-NeoPathContents -Path "C:\Windows\SoftwareDistribution\Download" -Label "Windows Update download cache" -KeepRoot
    if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
        try {
            Delete-DeliveryOptimizationCache -Force -IncludePinnedFiles -ErrorAction Stop
            Write-OK "Delivery Optimization cache cleared via supported cmdlet"
        } catch {
            $freedTotal += Remove-NeoPathContents -Path "C:\ProgramData\Microsoft\Windows\DeliveryOptimization\Cache" -Label "Delivery Optimization cache" -KeepRoot
        }
    } else {
        $freedTotal += Remove-NeoPathContents -Path "C:\ProgramData\Microsoft\Windows\DeliveryOptimization\Cache" -Label "Delivery Optimization cache" -KeepRoot
    }
    foreach ($svc in $services) { Start-Service -Name $svc -ErrorAction SilentlyContinue }

    Write-Host ""
    Write-Step "SYSTEM CACHE REFRESH"
    ipconfig /flushdns 2>&1 | Out-Null
    Write-OK "DNS cache flushed"
    netsh interface ip delete arpcache 2>&1 | Out-Null
    Write-OK "ARP cache cleared"
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-OK "Recycle Bin emptied"
    } catch {
        Write-Warn "Recycle Bin cleanup skipped: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Separator "" $Global:GREEN
    Write-Host "  $($Global:GREEN)$($Global:BOLD)CLEAN ALL JUNK COMPLETE$($Global:RESET)"
    Write-Host "  Total estimated freed: $([math]::Round($freedTotal, 2)) MB"
    Write-Host ""
}

function Install-CleanupSchedule {
    Write-ModuleHeader "09" "" "SCHEDULE CLEAN ALL JUNK"
    $ps = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    $neo = Join-Path $Script:Root "NeoOptimize.ps1"
    $args = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$neo`" -Action CleanAll -NoPause -AssumeYes"

    $action = New-ScheduledTaskAction -Execute $ps -Argument $args
    $trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]"03:30")
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -RunLevel Highest
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal
    Register-ScheduledTask -TaskName $Script:TaskName -InputObject $task -Force | Out-Null

    Write-OK "Scheduled task installed: $Script:TaskName"
    Write-Info "Daily time: 03:30, runs as SYSTEM, minimized PowerShell."
}

function Invoke-SmartBooster {
    Write-ModuleHeader "09" "" "SMART BOOSTER"
    Write-Info "Trimming working sets, refreshing shell caches, and triggering idle maintenance tasks."
    Write-Host ""

    $src = @"
using System;using System.Runtime.InteropServices;using System.Diagnostics;
public class NeoSmartBooster {
    [DllImport("psapi.dll")] public static extern int EmptyWorkingSet(IntPtr h);
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(int a,bool i,int pid);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    public static int Flush(){
        int n=0;
        foreach(Process p in Process.GetProcesses()){
            try{
                IntPtr h=OpenProcess(0x1F0FFF,false,p.Id);
                if(h!=IntPtr.Zero){ EmptyWorkingSet(h); CloseHandle(h); n++; }
            }catch{}
        }
        return n;
    }
}
"@
    try {
        if (-not ("NeoSmartBooster" -as [type])) {
            Add-Type -TypeDefinition $src -Language CSharp -ErrorAction Stop
        }
        $count = [NeoSmartBooster]::Flush()
        Write-OK "Working set trimmed for $count processes"
    } catch {
        Write-Warn "Working set trim failed: $($_.Exception.Message)"
    }

    rundll32.exe advapi32.dll,ProcessIdleTasks 2>&1 | Out-Null
    Write-OK "Windows idle maintenance tasks triggered"
    ipconfig /flushdns 2>&1 | Out-Null
    Write-OK "DNS cache flushed"
}

function Get-NeoVolumes {
    $vols = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" }
    if (-not $vols) {
        $vols = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
            [PSCustomObject]@{
                DriveLetter = $_.DeviceID.TrimEnd(":")
                FileSystemLabel = $_.VolumeName
                FileSystem = $_.FileSystem
                Size = $_.Size
                SizeRemaining = $_.FreeSpace
                HealthStatus = "Unknown"
            }
        }
    }
    return @($vols)
}

function Show-DiskStatus {
    Write-ModuleHeader "09" "" "DISK MANAGER STATUS"
    $reportPath = Join-Path $Script:MaintenanceReportDir "DiskStatus_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("NeoOptimize Disk Status $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $lines.Add("")

    Write-Step "VOLUMES"
    foreach ($vol in Get-NeoVolumes) {
        $sizeGb = if ($vol.Size) { [math]::Round($vol.Size / 1GB, 1) } else { 0 }
        $freeGb = if ($vol.SizeRemaining) { [math]::Round($vol.SizeRemaining / 1GB, 1) } else { 0 }
        $freePct = if ($sizeGb -gt 0) { [math]::Round(($freeGb / $sizeGb) * 100) } else { 0 }
        $text = "{0}: {1} {2}GB free / {3}GB total ({4}%), health {5}" -f $vol.DriveLetter, $vol.FileSystem, $freeGb, $sizeGb, $freePct, $vol.HealthStatus
        Write-Host "  $($Global:CYAN)$text$($Global:RESET)"
        $lines.Add($text)
    }

    Write-Host ""
    Write-Step "PHYSICAL DISKS"
    try {
        Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
            $sizeGb = [math]::Round($_.Size / 1GB, 1)
            $text = "{0} | {1} | {2} | {3}GB | {4}" -f $_.FriendlyName, $_.MediaType, $_.HealthStatus, $sizeGb, $_.OperationalStatus
            Write-Host "  $text"
            $lines.Add($text)
        }
    } catch {
        Write-Warn "Get-PhysicalDisk not available on this Windows edition."
    }

    $lines | Set-Content -Path $reportPath -Encoding UTF8
    Write-Host ""
    Write-OK "Disk status report: $reportPath"
}

function Invoke-DiskScan {
    Write-ModuleHeader "09" "" "SCAN DISK"
    foreach ($vol in Get-NeoVolumes) {
        $letter = [string]$vol.DriveLetter
        if (-not $letter) { continue }
        Write-Step "ONLINE SCAN $letter`:"
        try {
            Repair-Volume -DriveLetter $letter -Scan -ErrorAction Stop
            Write-OK "$letter`: online scan complete"
        } catch {
            chkdsk "$letter`:" /scan
        }
    }
}

function Invoke-DiskRepair {
    Write-ModuleHeader "09" "" "REPAIR DISK"
    Write-Warn "System drive repair can require reboot. NeoOptimize will schedule safe repair when online repair is not possible."
    if (-not (Confirm-NeoAction "  Schedule/perform disk repair for fixed volumes?" $true)) {
        Write-Skip "Disk repair"
        return
    }

    foreach ($vol in Get-NeoVolumes) {
        $letter = [string]$vol.DriveLetter
        if (-not $letter) { continue }
        Write-Step "REPAIR $letter`:"
        try {
            Repair-Volume -DriveLetter $letter -OfflineScanAndFix -ErrorAction Stop
            Write-OK "$letter`: offline scan and fix requested"
        } catch {
            if ($letter -ieq "C") {
                Start-Process -FilePath (Join-Path $env:SystemRoot "System32\cmd.exe") -ArgumentList "/d /c echo Y|chkdsk C: /F" -WindowStyle Hidden -Wait | Out-Null
                Write-OK "C: repair scheduled for next reboot"
            } else {
                Write-Warn "$letter`: fallback repair needs an exclusive lock. Scheduling safe check instead."
                $chkdskArgs = "/d /c echo N|chkdsk $letter`: /F"
                Start-Process -FilePath (Join-Path $env:SystemRoot "System32\cmd.exe") -ArgumentList $chkdskArgs -WindowStyle Hidden -Wait | Out-Null
            }
        }
    }
}

function Invoke-DiskOptimize {
    Write-ModuleHeader "09" "" "DEFRAG / TRIM"
    foreach ($vol in Get-NeoVolumes) {
        $letter = [string]$vol.DriveLetter
        if (-not $letter) { continue }
        Write-Step "OPTIMIZE $letter`:"
        try {
            Optimize-Volume -DriveLetter $letter -Analyze -Verbose
            Optimize-Volume -DriveLetter $letter -Verbose
            try { Optimize-Volume -DriveLetter $letter -ReTrim -Verbose } catch {}
            Write-OK "$letter`: optimize complete"
        } catch {
            defrag.exe "$letter`:" /O /U /V
        }
    }
}

function Invoke-HealthRepair {
    Write-ModuleHeader "09" "" "WINDOWS HEALTH REPAIR"
    Write-Info "Running DISM component cleanup and SFC integrity repair."
    Write-Host ""
    dism.exe /Online /Cleanup-Image /StartComponentCleanup
    dism.exe /Online /Cleanup-Image /RestoreHealth
    sfc.exe /scannow
    Write-OK "Windows health repair finished"
}

function Invoke-SmartOptimize {
    Write-ModuleHeader "09" "" "SMART OPTIMIZE"
    Invoke-CleanAllJunk
    Invoke-SmartBooster
    Invoke-DiskScan
    Invoke-DiskOptimize
    Write-Host ""
    Write-Separator "" $Global:GREEN
    Write-Host "  $($Global:GREEN)$($Global:BOLD)SMART OPTIMIZE COMPLETE$($Global:RESET)"
    Write-Host ""
}

function Show-MaintenanceMenu {
    while ($true) {
        Write-ModuleHeader "09" "" "MAINTENANCE MANAGER"
        Write-Host "  $($Global:CYAN)[1]$($Global:RESET) Clean all junk now"
        Write-Host "  $($Global:CYAN)[2]$($Global:RESET) Install scheduled daily cleanup"
        Write-Host "  $($Global:CYAN)[3]$($Global:RESET) Smart Booster"
        Write-Host "  $($Global:CYAN)[4]$($Global:RESET) Smart Optimize"
        Write-Host "  $($Global:CYAN)[5]$($Global:RESET) Disk status"
        Write-Host "  $($Global:CYAN)[6]$($Global:RESET) Scan disk"
        Write-Host "  $($Global:CYAN)[7]$($Global:RESET) Repair disk"
        Write-Host "  $($Global:CYAN)[8]$($Global:RESET) Defrag / TRIM"
        Write-Host "  $($Global:CYAN)[9]$($Global:RESET) Windows health repair"
        Write-Host "  $($Global:CYAN)[10]$($Global:RESET) System repair"
        Write-Host "  $($Global:CYAN)[0]$($Global:RESET) Back"
        Write-Host ""
        $choice = Read-NeoChoice "  Pilihan [0-10]" @("0","1","2","3","4","5","6","7","8","9","10") "0"
        switch ($choice) {
            "1" { Invoke-CleanAllJunk; Wait-AnyKey }
            "2" { Install-CleanupSchedule; Wait-AnyKey }
            "3" { Invoke-SmartBooster; Wait-AnyKey }
            "4" { Invoke-SmartOptimize; Wait-AnyKey }
            "5" { Show-DiskStatus; Wait-AnyKey }
            "6" { Invoke-DiskScan; Wait-AnyKey }
            "7" { Invoke-DiskRepair; Wait-AnyKey }
            "8" { Invoke-DiskOptimize; Wait-AnyKey }
            "9" { Invoke-HealthRepair; Wait-AnyKey }
            "10" { & (Join-Path $PSScriptRoot "10_SystemRepair.ps1"); Wait-AnyKey }
            default { return }
        }
    }
}

switch ($Mode) {
    "CleanAll" { Invoke-CleanAllJunk }
    "ScheduleClean" { Install-CleanupSchedule }
    "SmartBooster" { Invoke-SmartBooster }
    "SmartOptimize" { Invoke-SmartOptimize }
    "DeepScan" { & (Join-Path $PSScriptRoot "15_DeepScan.ps1") }
    "SystemDiagnostics" { & (Join-Path $PSScriptRoot "16_SystemDiagnostics.ps1") }
    "DiskStatus" { Show-DiskStatus }
    "DiskScan" { Invoke-DiskScan }
    "DiskRepair" { Invoke-DiskRepair }
    "DiskOptimize" { Invoke-DiskOptimize }
    "HealthRepair" { Invoke-HealthRepair }
    "SystemRepair" { & (Join-Path $PSScriptRoot "10_SystemRepair.ps1") }
    "Full" { Invoke-SmartOptimize; Install-CleanupSchedule }
    default { Show-MaintenanceMenu }
}

Write-Footer
Wait-AnyKey
