#Requires -RunAsAdministrator
<#
.SYNOPSIS  NeoOptimize - Automated Registry & Network Backup v4.0
.DESCRIPTION
    Silently backs up system registry, Wi-Fi profiles, and third-party drivers
    to a secure local directory to protect against failure.
#>

$ErrorActionPreference = "SilentlyContinue"
Write-Host "`n[BACKUP] ==================================================" -ForegroundColor Cyan
Write-Host "[BACKUP]  Automated System Backup v4.0                   " -ForegroundColor Cyan
Write-Host "[BACKUP] ==================================================`n" -ForegroundColor Cyan

$backupRoot = "$env:SystemDrive\NeoOptimize_Backups\$(Get-Date -Format 'yyyyMMdd_HHmm')"
if (-not (Test-Path $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null }

# ─── SECTION 1: Registry Backup ──────────────────────────────────────────────
Write-Host "  [1/3] Backing up Registry Hives..." -ForegroundColor Yellow
$regDir = "$backupRoot\Registry"
mkdir $regDir -Force | Out-Null
reg export HKLM\SOFTWARE "$regDir\HKLM_Software.reg" /y | Out-Null
reg export HKCU\SOFTWARE "$regDir\HKCU_Software.reg" /y | Out-Null
reg export HKLM\SYSTEM "$regDir\HKLM_System.reg" /y | Out-Null
reg export HKLM\SECURITY "$regDir\HKLM_Security.reg" /y | Out-Null
Write-Host "    [+] Registry backed up." -ForegroundColor Green

# ─── SECTION 2: Wi-Fi Profiles Backup ───────────────────────────────────────
Write-Host "`n  [2/3] Backing up Wi-Fi Profiles..." -ForegroundColor Yellow
$wifiDir = "$backupRoot\WiFi"
mkdir $wifiDir -Force | Out-Null
netsh wlan export profile key=absent folder="$wifiDir" | Out-Null
Write-Host "    [+] Wi-Fi profiles exported without secrets." -ForegroundColor Green

# ─── SECTION 3: Driver Backup ───────────────────────────────────────────────
Write-Host "`n  [3/3] Backing up Third-Party Drivers..." -ForegroundColor Yellow
$driverDir = "$backupRoot\Drivers"
mkdir $driverDir -Force | Out-Null
Export-WindowsDriver -Online -Destination $driverDir | Out-Null
Write-Host "    [+] Third-Party Drivers backed up." -ForegroundColor Green

Write-Host "`n[BACKUP] ==================================================" -ForegroundColor Cyan
Write-Host "[BACKUP]  All backups saved to: $backupRoot" -ForegroundColor Green
Write-Host "[BACKUP] ==================================================`n" -ForegroundColor Cyan
