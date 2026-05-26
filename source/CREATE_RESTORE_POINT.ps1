
# ╔══════════════════════════════════════════════════════════════════╗
# ║   NeoOptimize — System Restore Point Creator                     ║
# ║   Jalankan SEBELUM menggunakan NeoOptimize                       ║
# ╚══════════════════════════════════════════════════════════════════╝
#Requires -RunAsAdministrator

$ErrorActionPreference = "SilentlyContinue"
$ESC = [char]27

function clr($c) { "$ESC[${c}m" }
$G = clr 92; $Y = clr 93; $C = clr 96; $R = clr 0; $B = clr 1

Clear-Host
Write-Host ""
Write-Host "${C}${B}  ╔══════════════════════════════════════════════════════╗${R}"
Write-Host "${C}${B}  ║  🔄 NeoOptimize — System Restore Point Creator       ║${R}"
Write-Host "${C}${B}  ╚══════════════════════════════════════════════════════╝${R}"
Write-Host ""
Write-Host "  ${Y}Membuat System Restore Point sebelum optimasi...${R}"
Write-Host ""

try {
    Enable-ComputerRestore -Drive "C:\" -ErrorAction Stop
    $desc = "NeoOptimize Backup — $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    Checkpoint-Computer -Description $desc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    Write-Host "  ${G}✔ Restore Point berhasil dibuat:${R}"
    Write-Host "    $($Y)$desc${R}"
    Write-Host ""
    Write-Host "  ${C}Tips:${R} Untuk restore, buka${Y} System Properties → System Protection → System Restore${R}"
} catch {
    Write-Host "  Gagal membuat Restore Point: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Coba: Buka System Properties → System Protection → aktifkan dulu untuk drive C:" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Tekan tombol apapun..."
[void][System.Console]::ReadKey($true)
