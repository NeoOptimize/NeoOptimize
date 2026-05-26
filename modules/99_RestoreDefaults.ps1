#Requires -RunAsAdministrator
<# MODULE 99 — RESTORE DEFAULTS #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "99" "🔄" "RESTORE WINDOWS DEFAULTS"
Write-Warn "PERINGATAN: Modul ini menghapus override NeoOptimize high-risk dan mencoba restore dari backup lokal."
Write-Warn "Modul ini tidak mengaktifkan ulang protokol lama yang tidak aman seperti SMBv1."
if (-not (Confirm-NeoAction "Apakah Anda yakin ingin melanjutkan reset?")) {
    Write-Info "Dibatalkan oleh pengguna."
    Start-Sleep 2
    return
}

$changes = 0

# ── 1. Restore Network Settings (TCP & DNS) ───────────────────────────────────
Write-Step "RESTORING NETWORK SETTINGS"
Write-Host ""
# Reset TCP settings
netsh int tcp set supplemental template=internet congestionprovider=cubic 2>&1 | Out-Null
netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
netsh int tcp set global rsc=enabled 2>&1 | Out-Null
netsh int tcp set global ecncapability=disabled 2>&1 | Out-Null
Write-OK "TCP Congestion Control dikembalikan ke Default (CUBIC/Disabled ECN/Enabled RSC)"

# Remove DoH Policy
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "DoHPolicy" -ErrorAction SilentlyContinue
Write-OK "DNS-over-HTTPS (DoH) Group Policy dihapus"
$changes += 2

# ── 2. Restore Power & CPU (Game Mode Ultra revert) ───────────────────────────
Write-Host ""
Write-Step "RESTORING POWER & CPU SETTINGS"
Write-Host ""
# Restore Dynamic Tick & HPET overrides created by older aggressive builds.
bcdedit /deletevalue useplatformclock 2>&1 | Out-Null
bcdedit /deletevalue disabledynamictick 2>&1 | Out-Null
Write-OK "Boot timers dikembalikan ke default (Dynamic Tick & Platform Clock)"

# Delete HAGS override (let Windows manage)
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -ErrorAction SilentlyContinue
Write-OK "Hardware-Accelerated GPU Scheduling (HAGS) override dihapus"
$changes += 2

# ── 3. Restore Security (Zero-Trust revert) ───────────────────────────────────
Write-Host ""
Write-Step "RESTORING SECURITY SETTINGS"
Write-Host ""
# Remove LSA Protection Override
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPLBoot" -ErrorAction SilentlyContinue
Write-OK "LSA Protection (RunAsPPL) override dihapus"

# Remove SMBv1 override but do not re-enable SMBv1.
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "SMB1" -ErrorAction SilentlyContinue
Write-OK "SMBv1 override dihapus tanpa mengaktifkan SMBv1"
$changes += 2

# Remove VBS/HVCI policy overrides from experimental builds.
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" -Name "EnableVirtualizationBasedSecurity" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name "Enabled" -ErrorAction SilentlyContinue
Write-OK "VBS/HVCI policy overrides dihapus"
$changes++

# ── 4. Restore Services & AI/NPU ──────────────────────────────────────────────
Write-Host ""
Write-Step "RESTORING SERVICES & AI/NPU"
Write-Host ""
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "IoPageLockLimit" 0
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "LargeSystemCache" 0
Write-OK "Memory Management & AI Caching dikembalikan ke 0"

# Restore Hyper-V VMMS priority to Normal (32)
$vmms = Get-Process -Name "vmms" -ErrorAction SilentlyContinue
if ($vmms) {
    $vmms.PriorityClass = "Normal"
}
Write-OK "VMMS Process Priority dikembalikan ke Normal"
$changes += 2

# Restore backed up service startup modes if a local backup exists.
try {
    if (Restore-ServiceStartupBackup) { $changes++ }
} catch {
    Write-Warn "Restore service backup gagal: $($_.Exception.Message)"
}

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Separator "═" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)  ✅ RESTORE DEFAULTS SELESAI — $changes pengaturan dikembalikan$($Global:RESET)"
Write-Host ""
Write-Host "  $($Global:YELLOW)⚠  SANGAT DISARANKAN UNTUK RESTART PC SEKARANG.$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
