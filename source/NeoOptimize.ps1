
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    NeoOptimize v1.0 — Windows Optimizer & Agent
    Professional Tool for Computer Technicians

.DESCRIPTION
    One-Stop Solution untuk optimasi Windows 10/11.
    Dilengkapi 8 modul optimasi profesional.

.NOTES
    Author  : NeoOptimize Team
    Email   : neooptimizeofficial@gmail.com
    Version : 1.0
    Requires: PowerShell 5.1+, Windows 10/11, Run as Administrator
#>

param(
    [switch]$FullAuto,
    [switch]$NoPause,
    [switch]$AssumeYes,
    [switch]$ConfirmAll
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference    = "SilentlyContinue"

# ── Load Common Library ─────────────────────────────────────────────────────────
$LibPath = "$PSScriptRoot\lib\Common.ps1"
if (-not (Test-Path $LibPath)) {
    Write-Host "ERROR: lib\Common.ps1 not found. Pastikan semua file NeoOptimize ada di folder yang sama." -ForegroundColor Red
    pause; exit 1
}
. $LibPath

$Global:NeoOptimizeSkipPause = [bool]$NoPause
$Global:NeoOptimizeAssumeYes = [bool]$AssumeYes
$Global:NeoOptimizeConfirmAll = [bool]$ConfirmAll
if ($FullAuto) {
    $Global:NeoOptimizeNonInteractive = $true
    $Global:NeoOptimizeSkipPause = $true
}

# ── Admin Check ─────────────────────────────────────────────────────────────────
if (-not (Test-IsAdmin)) {
    Write-Host ""
    Write-Host "  ERROR: Jalankan sebagai Administrator!" -ForegroundColor Red
    Write-Host "  Klik kanan NeoOptimize.ps1 → 'Run as Administrator'" -ForegroundColor Yellow
    Start-Sleep 3
    exit 1
}

if ($FullAuto -and -not $AssumeYes) {
    Write-Err "Mode -FullAuto dari CLI membutuhkan -AssumeYes agar tidak menggantung di prompt konfirmasi."
    Write-Info "Contoh: powershell -NoProfile -ExecutionPolicy Bypass -File .\NeoOptimize.ps1 -FullAuto -AssumeYes"
    exit 2
}

# ── Module Runner ───────────────────────────────────────────────────────────────
function Invoke-Module {
    param($FileName)
    $path = "$PSScriptRoot\modules\$FileName"
    if (Test-Path $path) {
        . $path
    } else {
        Write-Host ""
        Write-Err "Modul tidak ditemukan: $FileName"
        Write-Info "Pastikan folder modules\ lengkap."
        Wait-AnyKey
    }
}

function Invoke-AgentConsole {
    $agentPath = Join-Path $PSScriptRoot "NeoOptimizeAgent.ps1"
    if (-not (Test-Path $agentPath)) {
        Write-Err "NeoOptimizeAgent.ps1 tidak ditemukan."
        Wait-AnyKey
        return
    }

    Write-NeoLogo -Compact
    Write-SectionHeader "🤖" "NEOOPTIMIZE AGENT" "Audit, score, report, scheduled task"
    Write-Host "  $($Global:CYAN)[1]$($Global:RESET) Audit & Score sekarang"
    Write-Host "  $($Global:CYAN)[2]$($Global:RESET) Remediate aman berdasarkan audit"
    Write-Host "  $($Global:CYAN)[3]$($Global:RESET) Install scheduled daily agent"
    Write-Host "  $($Global:CYAN)[4]$($Global:RESET) Status agent"
    Write-Host "  $($Global:CYAN)[5]$($Global:RESET) Uninstall scheduled agent"
    Write-Host "  $($Global:CYAN)[0]$($Global:RESET) Kembali"
    Write-Host ""
    $agentChoice = Read-NeoChoice "  Pilihan [0-5]" @("0","1","2","3","4","5") "1"

    switch ($agentChoice) {
        "1" { & $agentPath -Mode Audit }
        "2" { & $agentPath -Mode Remediate }
        "3" { & $agentPath -Mode Install }
        "4" { & $agentPath -Mode Status }
        "5" { & $agentPath -Mode Uninstall }
        default { return }
    }
    Wait-AnyKey
}

# ── System Summary Bar ──────────────────────────────────────────────────────────
function Write-SystemBar {
    $os    = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu   = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name
    $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB,1)
    $free  = [math]::Round($os.FreePhysicalMemory/1MB/1024,1)
    $build = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion
    $disk  = Get-PSDrive C | Select-Object @{N="Free";E={[math]::Round($_.Free/1GB,1)}},@{N="Used";E={[math]::Round($_.Used/1GB,1)}}

    Write-Host "  $($Global:DIM)┌─────────────────────────────────────────────────────────────────────┐$($Global:RESET)"
    Write-Host "  $($Global:DIM)│$($Global:RESET)  $($Global:WHITE)$($env:COMPUTERNAME.PadRight(15))$($Global:RESET)  $($Global:DIM)OS:$($Global:RESET) Win $build   $($Global:DIM)CPU:$($Global:RESET) $($cpu.Substring(0,[Math]::Min(28,$cpu.Length)))..."
    Write-Host "  $($Global:DIM)│$($Global:RESET)  $($Global:CYAN)RAM$($Global:RESET) ${free}GB/$($ramGB)GB free   $($Global:CYAN)Disk C:$($Global:RESET) $($disk.Free)GB free / $($disk.Used)GB used   $($Global:CYAN)User:$($Global:RESET) $($env:USERNAME)"
    Write-Host "  $($Global:DIM)└─────────────────────────────────────────────────────────────────────┘$($Global:RESET)"
}

# ── Menu Item Renderer ──────────────────────────────────────────────────────────
function Write-MenuItem {
    param($Key, $Icon, $Label, $Desc, $Hot = $false)
    $keyColor  = if ($Hot) { "$($Global:YELLOW)$($Global:BOLD)" } else { $Global:CYAN }
    Write-Host "  ${keyColor}[$Key]$($Global:RESET) $Icon $($Global:WHITE)$($Global:BOLD)$Label$($Global:RESET)"
    Write-Host "       $($Global:DIM)$Desc$($Global:RESET)"
}

# ── About Screen ─────────────────────────────────────────────────────────────────
function Show-About {
    Write-NeoLogo
    Write-Host ""
    Write-Host "  $($Global:CYAN)$($Global:BOLD)  TENTANG NEOOPTIMIZE$($Global:RESET)"
    Write-Host ""
    Write-Host "  $($Global:WHITE)Versi    :$($Global:RESET) $($Global:PRODUCT_VERSION)"
    Write-Host "  $($Global:WHITE)Platform :$($Global:RESET) Windows 10 / 11 (PowerShell 5.1+)"
    Write-Host "  $($Global:WHITE)Target   :$($Global:RESET) Teknisi Komputer & Power User"
    Write-Host ""
    Write-Separator "─" $Global:DIM
    Write-Host ""
    Write-Host "  $($Global:YELLOW)$($Global:BOLD)  📧 KONTAK & SUPPORT$($Global:RESET)"
    Write-Host ""
    Write-Host "  $($Global:WHITE)Email    :$($Global:RESET) $($Global:PRODUCT_EMAIL)"
    Write-Host ""
    Write-Host "  $($Global:YELLOW)$($Global:BOLD)  ☕ DONASI — Dukung Pengembangan NeoOptimize$($Global:RESET)"
    Write-Host ""
    Write-Host "  $($Global:GREEN)  ► BuyMeACoffee$($Global:RESET) : https://buymeacoffee.com/nol.eight"
    Write-Host "  $($Global:GREEN)  ► Saweria       $($Global:RESET): https://saweria.co/dtechtive"
    Write-Host "  $($Global:GREEN)  ► Dana (QR)     $($Global:RESET): https://ik.imagekit.io/dtechtive/Dana"
    Write-Host ""
    Write-Host "  $($Global:DIM)Setiap donasi sekecil apapun sangat berarti untuk"
    Write-Host "  pengembangan fitur baru dan pemeliharaan tool ini. Terima kasih!$($Global:RESET)"
    Write-Host ""
    Write-Separator "─" $Global:DIM
    Write-Host ""
    Write-Host "  $($Global:DIM)  NeoOptimize dibuat dengan ❤ untuk komunitas teknisi Indonesia.$($Global:RESET)"
    Write-Host ""
    Wait-AnyKey "Tekan tombol apapun untuk kembali ke menu utama..."
}

# ── Status Dashboard ──────────────────────────────────────────────────────────
function Show-Dashboard {
    Write-NeoLogo -Compact
    Write-SectionHeader "📊" "SYSTEM DASHBOARD" "Real-time system status"

    $snap = Get-SystemSnapshot

    # System Info Grid
    $info = @(
        @("💻 Computer",   $snap.ComputerName),
        @("👤 User",       $snap.User),
        @("🪟 Windows",    "$($snap.OS) [Build $($snap.OSBuild)]"),
        @("⚙️  CPU",        $snap.CPU),
        @("🧠 Cores",      "$($snap.CPUCores) cores / $($snap.CPUThreads) threads"),
        @("💾 RAM",        "$($snap.RAMFree) GB free / $($snap.RAMTotal) GB total"),
        @("🎮 GPU",        $snap.GPU),
        @("⏱️  Uptime",     "$($snap.Uptime.Days)d $($snap.Uptime.Hours)h $($snap.Uptime.Minutes)m"),
        @("🏭 Model",      "$($snap.Manufacturer) $($snap.Model)"),
        @("🔧 BIOS",       $snap.BIOSVersion)
    )
    foreach ($item in $info) {
        Write-Host "  $($Global:CYAN)$($item[0].PadRight(14))$($Global:RESET) $($item[1])"
    }

    Write-Host ""
    Write-Separator "─" $Global:DIM

    # Disk Usage
    Write-Host ""
    Write-Step "DISK USAGE"
    Write-Host ""
    Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 } | ForEach-Object {
        $total  = [math]::Round(($_.Used + $_.Free) / 1GB, 1)
        $used   = [math]::Round($_.Used / 1GB, 1)
        $free   = [math]::Round($_.Free / 1GB, 1)
        $pct    = [math]::Round(($_.Used / ($_.Used + $_.Free)) * 100)
        $fill   = [math]::Round($pct / 5)
        $bar    = "█" * $fill + "░" * (20 - $fill)
        $color  = if ($pct -gt 90) { $Global:RED } elseif ($pct -gt 75) { $Global:YELLOW } else { $Global:GREEN }
        Write-Host "  $($Global:WHITE)[$($_.Name):]$($Global:RESET)  $color$bar$($Global:RESET)  $pct%  $($Global:DIM)${used}GB / ${total}GB (${free}GB free)$($Global:RESET)"
    }

    Write-Host ""
    Write-Separator "─" $Global:DIM

    # Top Processes
    Write-Host ""
    Write-Step "TOP 5 PROSES (CPU)"
    Write-Host ""
    Write-Host "  $($Global:DIM)$("NAMA".PadRight(28)) $("CPU(s)".PadRight(10)) $("RAM(MB)".PadRight(10)) PID$($Global:RESET)"
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | ForEach-Object {
        $cpuS = [math]::Round($_.CPU, 1)
        $ramM = [math]::Round($_.WorkingSet / 1MB, 0)
        Write-Host "  $($_.Name.PadRight(28)) $("$cpuS".PadRight(10)) $("$ramM".PadRight(10)) $($_.Id)"
    }

    Write-Host ""
    Wait-AnyKey
}

# ── Safe Care Plan (legacy FullAuto entry point) ─────────────────────────────
function Invoke-FullGodMode {
    Write-NeoLogo
    Write-Host ""
    Write-Host "  $($Global:CYAN)$($Global:BOLD)  ╔═══════════════════════════════════════════════════════════╗$($Global:RESET)"
    Write-Host "  $($Global:CYAN)$($Global:BOLD)  ║  SAFE CARE PLAN — AUDIT-FIRST WINDOWS MAINTENANCE       ║$($Global:RESET)"
    Write-Host "  $($Global:CYAN)$($Global:BOLD)  ╚═══════════════════════════════════════════════════════════╝$($Global:RESET)"
    Write-Host ""
    Write-Host "  $($Global:YELLOW)Modul low-risk yang akan berjalan:$($Global:RESET)"
    Write-Host "  $($Global:DIM)  24 Device Snapshot  25 Benchmark  26 Privacy Review  27 Network Diagnostics$($Global:RESET)"
    Write-Host "  $($Global:DIM)  16 System Diagnostics  15 Deep Scan  01 Cleaner  Agent Audit$($Global:RESET)"
    Write-Host ""
    Write-Host "  $($Global:YELLOW)High-risk tuning tetap butuh konfirmasi manual atau -Enforce pada modul spesifik.$($Global:RESET)"
    Write-Host ""

    if (-not $Global:NeoOptimizeAssumeYes) {
        $confirm = Read-Host "  Ketik 'YES' untuk menjalankan Safe Care Plan"
        if ($confirm -ne "YES") {
            Write-Warn "Dibatalkan."
            Wait-AnyKey; return
        }
    } else {
        Write-Info "AssumeYes aktif: hanya modul Safe Care low-risk yang dijalankan."
    }

    # Create restore point first
    Write-Info "Membuat System Restore Point..."
    New-RestorePoint "NeoOptimize Safe Care Plan - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

    $prevNonInteractive = $Global:NeoOptimizeNonInteractive
    $prevSkipPause = $Global:NeoOptimizeSkipPause
    $Global:NeoOptimizeNonInteractive = $true
    $Global:NeoOptimizeSkipPause = $true

    $modules = @(
        @{File="24_DeviceSnapshot.ps1";     Icon="HW"; Name="Device Snapshot"},
        @{File="25_BenchmarkReport.ps1";    Icon="BENCH"; Name="Benchmark Baseline"},
        @{File="26_PrivacyReview.ps1";      Icon="PRV"; Name="Privacy Review"},
        @{File="27_NetworkDiagnostics.ps1"; Icon="NET"; Name="Network Diagnostics"},
        @{File="16_SystemDiagnostics.ps1"; Icon="CHK"; Name="System Diagnostics"},
        @{File="15_DeepScan.ps1";          Icon="SCAN"; Name="Deep Scan"},
        @{File="01_Cleaner.ps1";           Icon="CLEAN"; Name="System Cleaner"}
    )

    try {
        $total = $modules.Count
        $i = 0
        foreach ($m in $modules) {
            $i++
            Write-Host ""
            Write-Host "  $($Global:MAGENTA)$($Global:BOLD)[$i/$total] $($m.Icon) $($m.Name)$($Global:RESET)"
            Write-Separator "─" $Global:DIM
            $path = "$PSScriptRoot\modules\$($m.File)"
            if (Test-Path $path) {
                try { . $path } catch { Write-Warn "Error di modul $($m.File): $($_.Exception.Message)" }
            } else {
                Write-Err "Modul tidak ditemukan: $($m.File)"
            }
        }
    } finally {
        $Global:NeoOptimizeNonInteractive = $prevNonInteractive
        $Global:NeoOptimizeSkipPause = $prevSkipPause
    }

    # Generate HTML Report
    Write-Host ""
    Write-Info "Membuat laporan HTML..."
    $reportPath = "$PSScriptRoot\reports\SafeCare_$(Get-Date -f 'yyyyMMdd_HHmmss').html"
    $logEntries = $Global:LogBuf | ForEach-Object {
        $parts = $_ -split '\]\[|\[|\]'
        $level = if ($parts.Count -ge 3) { ConvertTo-HtmlSafe $parts[2] } else { "INFO" }
        $msg   = if ($parts.Count -ge 4) { ConvertTo-HtmlSafe $parts[3] } else { ConvertTo-HtmlSafe $_ }
        "<div class='entry'><span class='badge $level'>$level</span><span>$msg</span></div>"
    }
    $sections = "<div class='card'><h2>📋 Log Optimasi</h2>$($logEntries -join '')</div>"
    if (Export-HtmlReport "Safe Care Plan Report" $sections $reportPath) {
        Write-OK "Laporan HTML: $reportPath"
    }

    $agentPath = Join-Path $PSScriptRoot "NeoOptimizeAgent.ps1"
    if (Test-Path $agentPath) {
        Write-Info "Menjalankan NeoOptimize Agent post-audit..."
        try {
            & $agentPath -Mode Audit -Quiet -NoOpen
            Write-OK "Agent post-audit selesai. Cek folder reports\agent."
        } catch {
            Write-Warn "Agent post-audit gagal: $($_.Exception.Message)"
        }
    }

    Write-Host ""
    Write-Host "  $($Global:GREEN)$($Global:BOLD)  ╔══════════════════════════════════════════════════════════╗$($Global:RESET)"
    Write-Host "  $($Global:GREEN)$($Global:BOLD)  ║  SAFE CARE PLAN SELESAI — LAPORAN SIAP DIREVIEW         ║$($Global:RESET)"
    Write-Host "  $($Global:GREEN)$($Global:BOLD)  ╚══════════════════════════════════════════════════════════╝$($Global:RESET)"
    Write-Host ""
    Write-Host "  $($Global:YELLOW)Untuk tuning agresif, jalankan modul spesifik dan setujui prompt high-risk.$($Global:RESET)"
    Write-Host ""
    Wait-AnyKey
}

# ══════════════════════════════════════════════════════════════════════════════
#   MAIN MENU LOOP
# ══════════════════════════════════════════════════════════════════════════════
if ($FullAuto) {
    Invoke-FullGodMode
    exit 0
}

while ($true) {
    Write-NeoLogo
    Write-SystemBar
    Write-Host ""
    Write-Host "  $($Global:MAGENTA)$($Global:BOLD)◈ MENU UTAMA — PILIH MODUL$($Global:RESET)"
    Write-Host ""

    Write-MenuItem "0" "📊" "System Dashboard"          "Real-time info CPU, RAM, Disk, proses aktif"
    Write-MenuItem "1" "🧹" "System Cleaner"            "Hapus junk, temp, cache, prefetch, WER, DNS, browser"
    Write-MenuItem "2" "⚡" "Performance Optimizer"     "RAM flush, visual effects, pagefile, NTFS, boot"
    Write-MenuItem "3" "🔒" "Privacy & Telemetry"       "Matikan telemetri, Cortana, tracking, bloatware"
    Write-MenuItem "4" "🌐" "Network Optimizer"         "TCP/IP, DNS pilihan, QoS, Nagle, hosts file"
    Write-MenuItem "5" "🛡️" "Security Hardening"        "Defender, Firewall, SMBv1, TLS, exploit protection"
    Write-MenuItem "6" "⚙️" "Services Manager"          "5 profil: Home / Gaming / Workstation / Minimal / Restore"
    Write-MenuItem "7" "🔄" "Update & Driver Manager"   "Kontrol update, audit driver, winget upgrade"
    Write-MenuItem "8" "🔋" "Power & Gaming Mode"       "Ultimate power plan, GPU boost, mouse latency"
    Write-MenuItem "9" "🧠" "AI & NPU Optimizer"        "Audit AI/NPU; policy/cache tuning butuh konfirmasi"
    Write-MenuItem "10" "💾" "NVMe & DirectStorage"      "Audit BypassIO/TRIM; maintenance butuh konfirmasi"
    Write-MenuItem "11" "🐳" "Containerization (WSL)"    "Audit WSL/Hyper-V; .wslconfig butuh konfirmasi"
    Write-MenuItem "12" "🛡️" "Zero-Trust Security"       "Audit-first; VBS/HVCI/ASR butuh konfirmasi"
    Write-MenuItem "13" "🎮" "Game Mode Ultra"           "Audit gaming profile; tanpa BCDEdit otomatis"
    Write-MenuItem "14" "🌐" "Network QoS & TCP Tuning"  "Audit TCP/DoH; network policy butuh konfirmasi"
    Write-MenuItem "15" "🗑️" "Debloat Windows Apps"      "Pilih app bawaan Windows yang ingin dihapus"
    Write-MenuItem "16" "🚀" "Startup Optimizer"          "Audit/disable startup Run entries dan scheduled tasks"
    Write-MenuItem "17" "🧩" "Component Store Cleanup"    "Audit WinSxS dan DISM StartComponentCleanup"
    Write-MenuItem "18" "📜" "Event Log Maintenance"      "Export log EVTX, optional clear setelah backup"
    Write-MenuItem "19" "🧰" "Windows Feature Optimizer"  "Audit/disable optional legacy features"
    Write-MenuItem "20" "🛜" "Network Repair Toolkit"     "Flush DNS, renew DHCP, reset proxy/Winsock"
    Write-MenuItem "21" "🧾" "Device Snapshot"            "Inventaris hardware, driver, disk, BitLocker, TPM, Secure Boot"
    Write-MenuItem "22" "📈" "Before/After Benchmark"     "Capture baseline dan after report performa"
    Write-MenuItem "23" "🔎" "Privacy Review"             "Audit privacy tanpa mengunci kamera, mic, location"
    Write-MenuItem "24" "📡" "Network Diagnostics"        "Test konektivitas, DNS, route, TCP setting"
    Write-MenuItem "25" "🐳" "Container/Hyper-V Tuning"   "Audit WSL2/Hyper-V dan tulis .wslconfig bila disetujui"
    Write-MenuItem "26" "🛡️" "Zero-Trust Security"        "ASR audit mode dan hardening terkonfirmasi"
    Write-MenuItem "27" "🎮" "Game Mode Ultra"            "Game Mode/HAGS/GameDVR audit dan tuning aman"
    Write-MenuItem "28" "🧠" "AI & NPU Caching"           "Inventaris NPU/GPU dan policy batas cache AI"
    Write-MenuItem "29" "💾" "NVMe DirectStorage"         "Audit BypassIO, ReTrim, storage tiering"
    Write-MenuItem "30" "🔐" "Remote Access Readiness"    "Cek WinRM/OpenSSH/RDP/QEMU/RMM tanpa membuka akses"
    Write-MenuItem "31" "🧩" "Windows Update Repair"      "DISM/SFC dan reset update component terkonfirmasi"
    Write-MenuItem "32" "🔋" "Power Plan Tuning"          "Audit powercfg dan pilih power plan"
    Write-MenuItem "33" "🛡️" "Security Audit"             "Audit Defender, firewall, TPM, BitLocker, UAC, SMB"
    Write-MenuItem "N" "🤖" "NeoOptimize Agent"          "Audit otomatis, scoring, report, remediation aman"
    Write-Host ""
    Write-MenuItem "99" "🔄" "Restore Windows Defaults"  "Kembalikan pengaturan ke standar pabrik"
    Write-MenuItem "R" "🔄" "Buat Restore Point"         "System Restore Point sebelum optimasi"
    Write-MenuItem "A" "🔥" "Safe Care Plan"             "Audit, deep scan, cleaner ringan, dan report" -Hot $true
    Write-MenuItem "I" "ℹ️" "Tentang & Donasi"           "Info versi, kontak, link donasi"
    Write-MenuItem "Q" "🚪" "Keluar"                     "Tutup NeoOptimize"
    Write-Host ""
    Write-Footer
    Write-Host ""

    $choice = Read-Host "  $($Global:CYAN)$($Global:BOLD)Pilihan Anda$($Global:RESET)"

    switch ($choice.ToUpper().Trim()) {
        "0" { Show-Dashboard }
        "1" { Invoke-Module "01_Cleaner.ps1" }
        "2" { Invoke-Module "02_Performance.ps1" }
        "3" { Invoke-Module "03_Privacy.ps1" }
        "4" { Invoke-Module "04_Network.ps1" }
        "5" { Invoke-Module "05_Security.ps1" }
        "6" { Invoke-Module "06_Services.ps1" }
        "7" { Invoke-Module "07_Updates.ps1" }
        "8" { Invoke-Module "08_Power.ps1" }
        "9" { Invoke-Module "09_AIOptimizer.ps1" }
        "10" { Invoke-Module "11_StorageTiering.ps1" }
        "11" { Invoke-Module "12_Containerization.ps1" }
        "12" { Invoke-Module "13_ZeroTrustSecurity.ps1" }
        "13" { Invoke-Module "14_GameMode_Ultra.ps1" }
        "14" { Invoke-Module "17_NetworkQoS_eBPF.ps1" }
        "15" { Invoke-Module "18_DebloatWindows.ps1" }
        "16" { Invoke-Module "19_StartupOptimizer.ps1" }
        "17" { Invoke-Module "20_ComponentCleanup.ps1" }
        "18" { Invoke-Module "21_EventLogMaintenance.ps1" }
        "19" { Invoke-Module "22_WindowsFeatureOptimizer.ps1" }
        "20" { Invoke-Module "23_NetworkRepairToolkit.ps1" }
        "21" { Invoke-Module "24_DeviceSnapshot.ps1" }
        "22" { Invoke-Module "25_BenchmarkReport.ps1" }
        "23" { Invoke-Module "26_PrivacyReview.ps1" }
        "24" { Invoke-Module "27_NetworkDiagnostics.ps1" }
        "25" { Invoke-Module "28_ContainerHyperVTuning.ps1" }
        "26" { Invoke-Module "29_ZeroTrustSecurity.ps1" }
        "27" { Invoke-Module "30_GameModeUltra.ps1" }
        "28" { Invoke-Module "31_AINPUCaching.ps1" }
        "29" { Invoke-Module "32_StorageTiering.ps1" }
        "30" { Invoke-Module "33_RemoteAccessReadiness.ps1" }
        "31" { Invoke-Module "34_UpdateRepair.ps1" }
        "32" { Invoke-Module "35_PowerPlanTuning.ps1" }
        "33" { Invoke-Module "36_SecurityAudit.ps1" }
        "99" { Invoke-Module "99_RestoreDefaults.ps1" }
        "N" { Invoke-AgentConsole }
        "R" {
            Write-Info "Membuat System Restore Point..."
            New-RestorePoint "NeoOptimize Manual Backup — $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            Wait-AnyKey
        }
        "A" { Invoke-FullGodMode }
        "I" { Show-About }
        "Q" {
            Write-NeoLogo -Compact
            Write-Host ""
            Write-Host "  $($Global:GREEN)Terima kasih telah menggunakan NeoOptimize!$($Global:RESET)"
            Write-Host "  $($Global:DIM)Log tersimpan di: $($Global:LogFile)$($Global:RESET)"
            Write-Footer
            Write-Host ""
            exit 0
        }
        default {
            Write-Warn "Pilihan tidak valid: '$choice'"
            Start-Sleep 1
        }
    }
}
