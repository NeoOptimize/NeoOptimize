
#Requires -RunAsAdministrator
<# MODULE 02 — PERFORMANCE OPTIMIZER #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "02" "⚡" "PERFORMANCE OPTIMIZER"

$changes = 0

# ── 1. Visual Effects ──────────────────────────────────────────────────────────
Write-Step "VISUAL EFFECTS — Best Performance Mode"
Write-Host ""
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
Write-OK "Visual effects → Best Performance"
$changes++

# ── 2. RAM Flush ───────────────────────────────────────────────────────────────
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
	    Write-OK "RAM Working Set flushed ($n proses)"
    $changes++
} catch { Write-Warn "RAM flush: $($_.Exception.Message)" }

# ── 3. PageFile Optimization ───────────────────────────────────────────────────
	Write-Host ""
	Write-Step "PAGEFILE OPTIMIZATION"
	Write-Host ""
	$cs = Get-CimInstance Win32_ComputerSystem
	if (Confirm-NeoAction "  Pakai pagefile custom? Default produksi: Windows system-managed." $false) {
	    $ramMB = [math]::Round($cs.TotalPhysicalMemory / 1MB)
	    $pfMin = [math]::Max(1024, [math]::Min($ramMB, 16384))
	    $pfMax = [math]::Max(4096, [math]::Min($ramMB * 2, 32768))
	    $cs | Set-CimInstance -Property @{ AutomaticManagedPagefile = $false } -ErrorAction SilentlyContinue
	    Get-CimInstance Win32_PageFileSetting | Remove-CimInstance -ErrorAction SilentlyContinue
	    New-CimInstance -ClassName Win32_PageFileSetting -Property @{
	        Name = "C:\pagefile.sys"; InitialSize = $pfMin; MaximumSize = $pfMax
	    } -ErrorAction SilentlyContinue | Out-Null
	    Write-OK "PageFile custom: Min=${pfMin}MB  Max=${pfMax}MB"
	} else {
	    $cs | Set-CimInstance -Property @{ AutomaticManagedPagefile = $true } -ErrorAction SilentlyContinue
	    Write-OK "PageFile: Windows system-managed"
	}
	$changes++

# ── 4. NTFS Tweaks ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Step "NTFS PERFORMANCE TWEAKS"
Write-Host ""
fsutil behavior set disablelastaccess 1 2>&1 | Out-Null
Write-OK "Last Access timestamp: DISABLED"
fsutil behavior set disable8dot3 1 2>&1 | Out-Null
Write-OK "8.3 filename creation: DISABLED"
fsutil behavior set mftzone 2 2>&1 | Out-Null
Write-OK "MFT Zone: 2 (enlarged for large drives)"
$changes += 3

# ── 5. Processor Scheduling ────────────────────────────────────────────────────
Write-Host ""
Write-Step "PROCESSOR SCHEDULING"
Write-Host ""
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38
Write-OK "Processor scheduling: Foreground programs (38)"
$changes++

# ── 6. SysMain / Superfetch ────────────────────────────────────────────────────
Write-Host ""
Write-Step "SYSMAIN (SUPERFETCH)"
Write-Host ""
$sm = Get-Service SysMain -ErrorAction SilentlyContinue
if ($sm) {
    Stop-Service SysMain -Force -ErrorAction SilentlyContinue
    Set-Service  SysMain -StartupType Disabled -ErrorAction SilentlyContinue
    Write-OK "SysMain: DISABLED (optimal untuk SSD)"
} else { Write-Skip "SysMain" }

# ── 7. Memory Compression ──────────────────────────────────────────────────────
Write-Host ""
Write-Step "MEMORY COMPRESSION"
Write-Host ""
try {
    $mc = (Get-MMAgent -ErrorAction Stop).MemoryCompression
    if ($mc) {
        Disable-MMAgent -MemoryCompression -ErrorAction Stop
        Write-OK "Memory Compression: DISABLED (kurangi CPU overhead)"
    } else {
        Write-OK "Memory Compression: sudah disabled"
    }
    $changes++
} catch { Write-Warn "MMAgent tidak tersedia" }

# ── 8. Boot Configuration ──────────────────────────────────────────────────────
Write-Host ""
Write-Step "BOOT CONFIGURATION"
Write-Host ""
bcdedit /set quietboot yes 2>&1 | Out-Null
Write-OK "Quiet boot: enabled (tanpa Windows logo)"
bcdedit /set bootmenupolicy Standard 2>&1 | Out-Null
Write-OK "Boot menu: Standard"
bcdedit /debug off 2>&1 | Out-Null
Write-OK "Boot debug: OFF"
$changes += 3

# ── 9. Game DVR Off ────────────────────────────────────────────────────────────
Write-Host ""
Write-Step "XBOX GAME BAR & GAME DVR"
Write-Host ""
Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode" 2
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0
Write-OK "Game DVR & Xbox Game Bar: DISABLED"
$changes++

# ── 10. Startup Delay ──────────────────────────────────────────────────────────
Write-Host ""
Write-Step "STARTUP DELAY REMOVAL"
Write-Host ""
Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" "StartupDelayInMSec" 0
Write-OK "Explorer startup delay: 0ms"
$changes++

# ── 11. Audit Startup Items ────────────────────────────────────────────────────
Write-Host ""
Write-Step "STARTUP PROGRAMS AUDIT"
Write-Host ""
$startPaths = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
)
$startCount = 0
foreach ($sp in $startPaths) {
    if (Test-Path $sp) {
        $props = Get-ItemProperty -Path $sp -ErrorAction SilentlyContinue
        $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
	            $value = [string]$_.Value
	            Write-Host "  $($Global:DIM)  ► $($_.Name.PadRight(30)) $($value.Substring(0,[Math]::Min(60,$value.Length)))...$($Global:RESET)"
	            $startCount++
        }
    }
}
Write-Info "Ditemukan $startCount startup entry"

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Separator "═" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)  ✅ PERFORMANCE OPTIMIZER SELESAI — $changes perubahan diterapkan$($Global:RESET)"
Write-Host ""
Write-Host "  $($Global:YELLOW)⚠  Beberapa perubahan memerlukan RESTART untuk efek penuh.$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
