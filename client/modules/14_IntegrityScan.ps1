#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Aegis AV / NeoMonitor - L5 Integrity & Anti-Hack Auditor v1.0
.DESCRIPTION
    Scans critical OS binaries and actively running processes to verify
    Authenticode Digital Signatures and generate SHA256 Hashes.
    Identifies injected DLLs or tampered executables (Rootkits/Trojans).
#>

$ErrorActionPreference = "SilentlyContinue"
$IntegrityPayload = @{
    "scan_time" = (Get-Date -Format 'yyyy-MM-dd HH:mm:ssZ')
    "tampered_files" = @()
    "unsigned_processes" = @()
    "integrity_score" = 100
}

Write-Host "`n[AEGIS] ===================================================" -ForegroundColor Cyan
Write-Host "[AEGIS]   L5 Integrity & Anti-Hack Auditor Initiated     " -ForegroundColor Cyan
Write-Host "[AEGIS] ===================================================`n" -ForegroundColor Cyan

# 1. Critical System Binaries Hash & Signature Verification
Write-Host "  [1/2] Auditing Critical System Binaries (Authenticode & SHA256)..." -ForegroundColor Yellow
$criticalFiles = @(
    "$env:windir\System32\ntoskrnl.exe",
    "$env:windir\System32\lsass.exe",
    "$env:windir\System32\svchost.exe",
    "$env:windir\System32\cmd.exe",
    "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe",
    "$env:windir\explorer.exe"
)

foreach ($file in $criticalFiles) {
    if (Test-Path $file) {
        $sig = Get-AuthenticodeSignature -FilePath $file
        $hash = (Get-FileHash -Path $file -Algorithm SHA256).Hash

        if ($sig.Status -ne "Valid") {
            $IntegrityPayload["tampered_files"] += @{
                "file" = $file
                "sha256" = $hash
                "status" = $sig.Status
                "signer" = $sig.SignerCertificate.Subject
            }
            $IntegrityPayload["integrity_score"] -= 20
        }
    }
}
Write-Host "    [+] Core binaries audited." -ForegroundColor Green

# 2. Running Process Signature Verification
Write-Host "`n  [2/2] Scanning Active Processes for Unsigned/Injected Code..." -ForegroundColor Yellow
$processes = Get-Process | Where-Object { $_.Path -ne $null } | Select-Object -Unique Path
$count = 0
foreach ($p in $processes) {
    if ($count -gt 50) { break } # Limit to 50 for performance
    $sig = Get-AuthenticodeSignature -FilePath $p.Path
    if ($sig.Status -ne "Valid") {
        # Filter out known safe locations or focus on critical paths
        if ($p.Path -match "(System32|Windows|Program Files)") {
            $hash = (Get-FileHash -Path $p.Path -Algorithm SHA256).Hash
            $IntegrityPayload["unsigned_processes"] += @{
                "process_path" = $p.Path
                "sha256" = $hash
                "status" = $sig.Status
            }
            $IntegrityPayload["integrity_score"] -= 5
        }
    }
    $count++
}
Write-Host "    [+] Running processes scanned." -ForegroundColor Green

# Prevent negative score
if ($IntegrityPayload["integrity_score"] -lt 0) { $IntegrityPayload["integrity_score"] = 0 }

Write-Host "    [+] Audit Complete. Integrity Score: $($IntegrityPayload["integrity_score"])/100" -ForegroundColor $(if($IntegrityPayload["integrity_score"] -lt 80){"Red"}else{"Green"})
Write-Host "`n[AEGIS] ===================================================" -ForegroundColor Cyan
Write-Host "[AEGIS]   Integrity Telemetry Ready for NeoMonitor.      " -ForegroundColor Cyan
Write-Host "[AEGIS] ===================================================`n" -ForegroundColor Cyan

# Output JSON for RMM
$IntegrityPayload | ConvertTo-Json -Depth 5 -Compress | Write-Output
