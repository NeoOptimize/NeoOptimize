#Requires -RunAsAdministrator
<# MODULE 02  PERFORMANCE OPTIMIZER #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "02" "" "PERFORMANCE OPTIMIZER & BOOT TUNER"
if (-not (Test-NeoHighRiskConsent -ActionName "Performance Optimizer" -RiskLevel "High" -Reason "Mengubah visual effects, NTFS, service SysMain, memory compression, boot flags, dan GameDVR.")) {
    Wait-AnyKey
    return
}

# Fetch safeguards dynamically
$safeguards = Get-NeoHardwareSafeguards
$changes = 0

# 1. Next-Gen Visual Effects Tuning (Safe & Premium)
Write-Step "VISUAL EFFECTS OPTIMIZATION"
Write-Host ""
if ($safeguards.BypassAggressiveVisuals) {
    Write-OK "Bypass Visual Degradation: Sistem berspesifikasi tinggi terdeteksi (RAM > 16GB, Core > 8)."
    Write-OK "Visual effects dipertahankan agar UI tetap terasa premium & modern."
} else {
    $vfx = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    Set-Reg $vfx "VisualFXSetting" 2
    Set-Reg "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" "String"

    $advKeys = @{
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" = @{
            "ListviewAlphaSelect" = 0; "ListviewShadow" = 0; "TaskbarAnimations" = 0; "ExtendedUIHoverTime" = 1
        }
        "HKCU:\Software\Microsoft\Windows\DWM" = @{
            "EnableAeroPeek" = 0; "AlwaysHibernateThumbnails" = 0
        }
    }
    foreach ($path in $advKeys.Keys) {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        foreach ($kv in $advKeys[$path].GetEnumerator()) {
            Set-ItemProperty -Path $path -Name $kv.Key -Value $kv.Value -ErrorAction SilentlyContinue
        }
    }
    Write-OK "Visual effects: Best Performance (Efek animasi dimatikan untuk performa optimal)"
    $changes++
}

# 2. RAM Flush
Write-Host ""
Write-Step "RAM WORKING SET FLUSH"
Write-Host ""
$src = @"
using System;using System.Runtime.InteropServices;using System.Diagnostics;
public class RamFlusher {
    [DllImport("psapi.dll")] public static extern int EmptyWorkingSet(IntPtr h);
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(int a,bool i,int pid);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    public static int FlushAll(){
        int n=0;
        foreach(Process p in Process.GetProcesses()){
            try{IntPtr h=OpenProcess(0x1F0FFF,false,p.Id);
            if(h!=IntPtr.Zero){EmptyWorkingSet(h);CloseHandle(h);n++;}}catch{}
        }return n;
    }
}
"@
try {
    if (-not ("RamFlusher" -as [type])) {
        Add-Type -TypeDefinition $src -Language CSharp -ErrorAction Stop
    }
    $n = [RamFlusher]::FlushAll()
    Write-OK "RAM Working Set flushed ($n proses berhasil dibersihkan)"
    $changes++
} catch { 
    Write-Warn "RAM flush gagal: $($_.Exception.Message)" 
}

# 3. PageFile Optimization
Write-Host ""
Write-Step "PAGEFILE OPTIMIZATION"
Write-Host ""
$cs = Get-CimInstance Win32_ComputerSystem
if (-not $Global:NeoOptimizeNonInteractive) {
    if (Confirm-NeoAction "  Gunakan parameter Pagefile custom berdasarkan jumlah RAM Anda?" $false) {
        $ramMB = [math]::Round($cs.TotalPhysicalMemory / 1MB)
        $pfMin = [math]::Max(1024, [math]::Min($ramMB, 16384))
        $pfMax = [math]::Max(4096, [math]::Min($ramMB * 2, 32768))
        $cs | Set-CimInstance -Property @{ AutomaticManagedPagefile = $false } -ErrorAction SilentlyContinue
        Get-CimInstance Win32_PageFileSetting | Remove-CimInstance -ErrorAction SilentlyContinue
        New-CimInstance -ClassName Win32_PageFileSetting -Property @{
            Name = "C:\pagefile.sys"; InitialSize = $pfMin; MaximumSize = $pfMax
        } -ErrorAction SilentlyContinue | Out-Null
        Write-OK "PageFile custom: Min=${pfMin}MB | Max=${pfMax}MB"
        $changes++
    } else {
        $cs | Set-CimInstance -Property @{ AutomaticManagedPagefile = $true } -ErrorAction SilentlyContinue
        Write-OK "PageFile: Windows system-managed (default)"
    }
} else {
    Write-OK "PageFile: dipertahankan default (System-managed)"
}

# 4. NTFS Tweaks
Write-Host ""
Write-Step "NTFS PERFORMANCE TWEAKS"
Write-Host ""
fsutil behavior set disablelastaccess 1 2>&1 | Out-Null
Write-OK "Last Access timestamp: DISABLED"
fsutil behavior set disable8dot3 1 2>&1 | Out-Null
Write-OK "8.3 filename creation: DISABLED"
fsutil behavior set mftzone 2 2>&1 | Out-Null
Write-OK "MFT Zone: 2 (Enlarged untuk drive besar)"
$changes += 3

# 5. Processor Scheduling
Write-Host ""
Write-Step "PROCESSOR SCHEDULING"
Write-Host ""
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38
Write-OK "Processor scheduling: Foreground programs optimized (38)"
$changes++

# 6. SysMain / Superfetch (HDD Safeguarded)
Write-Host ""
Write-Step "SYSMAIN (SUPERFETCH) OPTIMIZATION"
Write-Host ""
if ($safeguards.BypassDisableSysMain) {
    Write-OK "Bypass SysMain Tweak: Mechanical HDD terdeteksi."
    Write-OK "SysMain dipertahankan ACTIVE untuk mempercepat loading block file pada HDD."
} else {
    $sm = Get-Service SysMain -ErrorAction SilentlyContinue
    if ($sm) {
        Stop-Service SysMain -Force -ErrorAction SilentlyContinue
        Set-Service  SysMain -StartupType Disabled -ErrorAction SilentlyContinue
        Write-OK "SysMain: DISABLED (Optimal untuk drive SSD)"
        $changes++
    } else { 
        Write-Skip "SysMain sudah nonaktif" 
    }
}

# 7. Memory Compression
Write-Host ""
Write-Step "MEMORY COMPRESSION"
Write-Host ""
try {
    $mc = (Get-MMAgent -ErrorAction Stop).MemoryCompression
    if ($mc) {
        Disable-MMAgent -MemoryCompression -ErrorAction Stop
        Write-OK "Memory Compression: DISABLED (Mengurangi overhead CPU)"
    } else {
        Write-OK "Memory Compression: sudah dinonaktifkan"
    }
    $changes++
} catch { 
    Write-Warn "CIM MMAgent tidak tersedia" 
}

# 8. Active Boot Maintenance & msconfig acceleration
Write-Host ""
Write-Step "BOOT MAINTENANCE & MSCONFIG OPTIMIZATION"
Write-Host ""
$bootChanges = Invoke-ActiveSystemMaintenance
$changes += $bootChanges

# 9. Quiet Boot Options
Write-Host ""
Write-Step "QUIET BOOT OPTIONS"
Write-Host ""
bcdedit /set quietboot yes 2>&1 | Out-Null
Write-OK "Quiet boot: ENABLED (Booting bersih tanpa logo)"
bcdedit /set bootmenupolicy Standard 2>&1 | Out-Null
Write-OK "Boot menu policy: Standard"
bcdedit /debug off 2>&1 | Out-Null
Write-OK "Boot debug mode: DISABLED"
$changes += 3

# 10. Startup Delay & Game DVR
Write-Host ""
Write-Step "STARTUP DELAY & TELEMETRY DVR"
Write-Host ""
Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" "StartupDelayInMSec" 0
Write-OK "Explorer startup delay: 0ms (Instan startup)"
Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode" 2
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0
Write-OK "Xbox Game DVR & Game Bar: DISABLED"
$changes += 2

# Refresh Cached Health Results
try {
    $Global:NeoHealthResult = Invoke-NeoHealthScreening -Run $true
} catch {}

# Summary
Write-Host ""
Write-Separator "" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)   PERFORMANCE OPTIMIZER SELESAI  $changes perubahan diterapkan$($Global:RESET)"
Write-Host ""
Write-Host "  $($Global:YELLOW)  Beberapa perubahan memerlukan RESTART untuk efek penuh.$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
