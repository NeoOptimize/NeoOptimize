param(
    [switch]$Enforce
)

#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Aegis AV / NeoMonitor - L2 Autoimmune & Ransomware Shield v1.0
.DESCRIPTION
    Enables Attack Surface Reduction (ASR) rules, Controlled Folder Access,
    and Network Protection to block ransomware, zero-days, and fileless malware.
#>

$ErrorActionPreference = "SilentlyContinue"
$mpAction = if ($Enforce) { "Enabled" } else { "AuditMode" }
$modeLabel = if ($Enforce) { "ENFORCE" } else { "AUDIT" }

Write-Host "`n[AEGIS] ===================================================" -ForegroundColor Cyan
Write-Host "[AEGIS]   L2 Autoimmune & Ransomware Shield ($modeLabel) " -ForegroundColor Cyan
Write-Host "[AEGIS] ===================================================`n" -ForegroundColor Cyan

# 1. Enable Controlled Folder Access (Anti-Ransomware)
Write-Host "  [1/3] Configuring Controlled Folder Access..." -ForegroundColor Yellow
Set-MpPreference -EnableControlledFolderAccess $mpAction
Write-Host "    [+] Controlled Folder Access: $modeLabel" -ForegroundColor Green

# 2. Enable Network Protection (Blocks C2 and Phishing domains at OS level)
Write-Host "`n  [2/3] Configuring Windows Defender Network Protection..." -ForegroundColor Yellow
Set-MpPreference -EnableNetworkProtection $mpAction
Write-Host "    [+] Network Protection: $modeLabel" -ForegroundColor Green

# 3. Apply Attack Surface Reduction (ASR) Rules
Write-Host "`n  [3/3] Applying Attack Surface Reduction (ASR) rules..." -ForegroundColor Yellow
$asrRules = @{
    "Block executable content from email client and webmail" = "be9ba2d9-53ea-4cdc-84e5-9b1eeee46550"
    "Block all Office applications from creating child processes" = "d4f940ab-401b-4efc-aadc-ad5f3c50688a"
    "Block Office applications from creating executable content" = "3b576869-a4ec-4529-8536-b80a7769e899"
    "Block Office applications from injecting code into other processes" = "75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84"
    "Block JavaScript or VBScript from launching downloaded executable content" = "d3e037e1-3eb8-44c8-a917-57927947596d"
    "Block execution of potentially obfuscated scripts" = "5beb7efe-fd9a-4556-801d-275e5ffc04cc"
    "Block Win32 API calls from Office macros" = "92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b"
    "Use advanced protection against ransomware" = "c1db55ab-c21a-4637-bb3f-a12568109d35"
    "Block credential stealing from the Windows local security authority subsystem (lsass.exe)" = "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2"
    "Block process creations originating from PSExec and WMI commands" = "d1e49c48-f40d-4fc6-0ad5-eca78b1d34eb"
    "Block untrusted and unsigned processes that run from USB" = "b2b3f03d-6a65-4f7b-93ce-7da645c09670"
    "Block Office communication application from creating child processes" = "26190899-1602-49e8-8b27-eb1d0a1ce869"
    "Block Adobe Reader from creating child processes" = "7674ba52-37eb-4a4f-8641-5e5ce701f44e"
    "Block persistence through WMI event subscription" = "e6db77e5-3df2-4cf1-b95a-636979351e5b"
}

foreach ($rule in $asrRules.Keys) {
    Add-MpPreference -AttackSurfaceReductionRules_Ids $asrRules[$rule] -AttackSurfaceReductionRules_Actions $mpAction
}
Write-Host "    [+] ASR rules applied in $modeLabel mode." -ForegroundColor Green

Write-Host "`n[AEGIS] ===================================================" -ForegroundColor Cyan
Write-Host "[AEGIS]   L2 Autoimmune policy applied in $modeLabel mode. " -ForegroundColor Green
Write-Host "[AEGIS] ===================================================`n" -ForegroundColor Cyan
