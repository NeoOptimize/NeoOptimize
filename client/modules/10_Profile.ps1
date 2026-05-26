#Requires -RunAsAdministrator
<# MODULE 10  OPTIMIZATION PROFILE SELECTOR #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "10" "" "OPTIMIZATION PROFILE SETUP"
Write-Host "  Pilihlah profil optimasi yang paling sesuai dengan pola penggunaan komputer Anda."
Write-Host "  Semua perubahan didukung oleh Next-Gen Active safeguard engine."
Write-Host ""

# Show current active profile if configured
$currentProfile = "General / Normal"
$profileReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\NeoOptimize" -Name "ActiveProfile" -ErrorAction SilentlyContinue
if ($profileReg) {
    $currentProfile = $profileReg.ActiveProfile
}

Write-Host "  Profil Aktif Saat Ini: $($Global:CYAN)$($Global:BOLD)$($currentProfile)$($Global:RESET)"
Write-Host ""
Write-Separator "" $Global:DIM
Write-Host ""

Write-MenuItem "1" "" "Work / Office Profile" "Fokus pada kestabilan, efisiensi daya, service perkantoran, dan kompresi memori seimbang."
Write-MenuItem "2" "" "Gaming / Ultimate Performance" "Fokus pada FPS maksimal, latensi mouse/keyboard minimal, Ultimate Power Plan, GPU boost, dan UWP bloatware nonaktif."
Write-MenuItem "3" "" "General / Balanced (Normal)" "Keseimbangan antara performa, konsumsi daya standar, dan kompatibilitas penuh aplikasi Windows."
Write-MenuItem "0" "" "Kembali" "Kembali ke menu utama"
Write-Host ""

$choice = Read-NeoChoice "  Pilih Profile [0-3]" @("0","1","2","3") "0"

switch ($choice) {
    "1" {
        Write-Info "Menerapkan profil: Work / Office..."
        $applied = Set-NeoOptimizationProfile -Profile "Work"
        if ($applied) {
            Write-OK "Profil WORK berhasil diterapkan! Services office & RAM compression diaktifkan."
        } else {
            Write-Warn "Gagal menerapkan profil WORK secara penuh."
        }
    }
    "2" {
        Write-Info "Menerapkan profil: Gaming / Ultimate Performance..."
        $applied = Set-NeoOptimizationProfile -Profile "Gaming"
        if ($applied) {
            Write-OK "Profil GAMING berhasil diterapkan! Ultimate Power, GPU boost, & latensi minimal aktif."
        } else {
            Write-Warn "Gagal menerapkan profil GAMING secara penuh."
        }
    }
    "3" {
        Write-Info "Menerapkan profil: General / Normal Balanced..."
        $applied = Set-NeoOptimizationProfile -Profile "General"
        if ($applied) {
            Write-OK "Profil GENERAL / BALANCED berhasil diterapkan! Kompatibilitas Windows penuh."
        } else {
            Write-Warn "Gagal menerapkan profil GENERAL secara penuh."
        }
    }
    "0" {
        return
    }
}

# Refresh health screening data
try {
    $Global:NeoHealthResult = Invoke-NeoHealthScreening -Run $true
} catch {}

Write-Host ""
Write-Footer
Wait-AnyKey
