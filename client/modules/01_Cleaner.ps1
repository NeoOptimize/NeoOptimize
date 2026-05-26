#Requires -RunAsAdministrator
<# MODULE 01  SYSTEM CLEANER #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "01" "" "SYSTEM CLEANER"
Write-Info "Memulai pembersihan sistem tingkat dalam dengan CPU safeguard..."
Write-Host ""

# Enforce priority safeguard
try {
    ([System.Diagnostics.Process]::GetCurrentProcess()).PriorityClass = 'BelowNormal'
} catch {}

# Create Restore Point if not run headlessly
if (-not $Global:NeoOptimizeNonInteractive) {
    if (Confirm-NeoAction "  Buat System Restore Point sebelum melakukan pembersihan ekstrim?" $true) {
        Write-Info "Membuat restore point..."
        New-RestorePoint "NeoOptimize Deep Cleaner  $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    }
}

# 1. Run Next-Gen Extreme Junk Cleaner
Write-Step "MENJALANKAN NEXT-GEN EXTREME JUNK CLEANER"
Write-Host ""
$res = Invoke-ExtremeJunkCleaner

# 2. Font Cache Rebuild
Write-Host ""
Write-Step "REBUILD FONT CACHE"
Write-Host ""
try {
    Stop-Service FontCache -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\System32\FNTCACHE.DAT" -Force -ErrorAction SilentlyContinue
    Start-Service FontCache -ErrorAction SilentlyContinue
    Write-OK "Font Cache berhasil dibersihkan dan dibangun ulang"
} catch {
    Write-Warn "Gagal mereset Font Cache"
}

# 3. Windows.old Check
Write-Host ""
Write-Step "WINDOWS.OLD VERIFICATION"
Write-Host ""
if (Test-Path "C:\Windows.old") {
    $wOldSize = Get-FolderSizeMB "C:\Windows.old"
    Write-Warn "Windows.old (Sisa upgrade sistem lama) terdeteksi: ${wOldSize} MB"
    Write-Info "Gunakan utilitas Disk Cleanup 'Previous Windows installation(s)' untuk menghapusnya secara aman."
} else {
    Write-OK "Folder residu Windows.old tidak ditemukan (Sistem Bersih)"
}

# 4. Automated Disk Cleanup (CleanMgr Integration)
Write-Host ""
Write-Step "AUTOMATED DISK CLEANUP (CleanMgr)"
Write-Host ""
$cleanFlags = @(
    "Active Setup Temp Folders","BranchCache","Content Indexer Cleaner",
    "Device Driver Packages","Downloaded Program Files","Internet Cache Files",
    "Memory Dump Files","Old ChkDsk Files","Previous Installations",
    "Recycle Bin","Setup Log Files","System error memory dump files",
    "System error minidump files","Temporary Files","Temporary Setup Files",
    "Thumbnail Cache","Update Cleanup","Windows Defender",
    "Windows Error Reporting Archive Files","Windows Error Reporting Queue Files",
    "Windows ESD installation files","Windows Upgrade Log Files"
)
$regBase = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
foreach ($f in $cleanFlags) {
    $rp = Join-Path $regBase $f
    if (Test-Path $rp) {
        New-ItemProperty -Path $rp -Name StateFlags0099 -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    }
}
Write-Info "Menjalankan Windows cleanmgr.exe (Sagerun 99)..."
Start-Process cleanmgr.exe -ArgumentList "/sagerun:99" -Wait -ErrorAction SilentlyContinue
Write-OK "Windows CleanMgr selesai"

# Refresh Cached Health Results
try {
    $Global:NeoHealthResult = Invoke-NeoHealthScreening -Run $true
} catch {}

# Summary
Write-Host ""
Write-Separator "" $Global:GREEN
Write-Host ""
Write-Host "  $($Global:GREEN)$($Global:BOLD)   EXTREME DEEP CLEANER SELESAI$($Global:RESET)"
Write-Host "  $($Global:WHITE)  Total sampah dibebaskan  : $($Global:GREEN)$($Global:BOLD)$($res.TotalFreedMB) MB$($Global:RESET)"
Write-Host "  $($Global:WHITE)  File sampah dihapus       : $($Global:CYAN)$($res.FilesDeleted)$($Global:RESET)"
Write-Host "  $($Global:WHITE)  Folder kosong dibersihkan  : $($Global:CYAN)$($res.FoldersCleaned)$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
