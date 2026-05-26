#Requires -RunAsAdministrator
<# MODULE 34 - WINDOWS UPDATE REPAIR #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "34" "UPD" "WINDOWS UPDATE REPAIR"

$services = @("wuauserv", "bits", "cryptsvc", "msiserver", "TrustedInstaller", "UsoSvc")
$serviceStatus = @(Get-Service -Name $services | Select-Object Name, Status, StartType)
$lastHotfix = @(Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 10 HotFixID, Description, InstalledOn, InstalledBy)
$events = @(Get-WinEvent -LogName "Microsoft-Windows-WindowsUpdateClient/Operational" -MaxEvents 20 | Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message)
$pendingReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"

Write-Step "WINDOWS UPDATE STATUS"
Write-Host ""
foreach ($svc in $serviceStatus) {
    Write-Info ("{0,-18} {1,-10} {2}" -f $svc.Name, $svc.Status, $svc.StartType)
}
Write-Info ("Pending reboot flag: {0}" -f $pendingReboot)
if ($lastHotfix.Count -gt 0) {
    Write-Info ("Latest hotfix: {0} installed {1}" -f $lastHotfix[0].HotFixID, $lastHotfix[0].InstalledOn)
}

$dir = Join-Path $Global:LogDir "updates"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$report = [PSCustomObject]@{
    captured_at = (Get-Date).ToString("o")
    services = $serviceStatus
    pending_reboot = $pendingReboot
    last_hotfixes = $lastHotfix
    recent_events = $events
}
$path = Join-Path $dir ("update-repair_audit_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
Write-OK "Windows Update audit report: $path"

if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) {
    Write-Warn "Non-interactive mode: audit only."
    Wait-AnyKey
    return
}

Write-Host ""
Write-Host "  [1] Audit only"
Write-Host "  [2] Run DISM CheckHealth and SFC verifyonly"
Write-Host "  [3] Run DISM RestoreHealth and SFC scannow"
Write-Host "  [4] Reset Windows Update components (high-risk; -Enforce required)"
Write-Host ""
$choice = Read-NeoChoice "  Pilihan [1-4]" @("1","2","3","4") "1"

if ($choice -eq "2" -and (Confirm-NeoAction "Run DISM CheckHealth and SFC verifyonly?" $false)) {
    & dism.exe /Online /Cleanup-Image /CheckHealth
    & sfc.exe /verifyonly
    Write-OK "Read-only health verification completed."
}

if ($choice -eq "3" -and (Confirm-NeoAction "Run DISM RestoreHealth and SFC /scannow? This can take several minutes." $false)) {
    & dism.exe /Online /Cleanup-Image /RestoreHealth
    & sfc.exe /scannow
    Write-OK "Windows repair commands completed. Review CBS.log if errors remain."
}

if ($choice -eq "4") {
    if (Test-NeoHighRiskConsent -ActionName "WindowsUpdateComponentReset" -RiskLevel "High" -Reason "Reset akan menghentikan service update dan mengganti nama SoftwareDistribution serta catroot2. Reboot mungkin diperlukan.") {
        if (Confirm-NeoAction "Reset Windows Update components now?" $false) {
            foreach ($svc in @("wuauserv", "bits", "cryptsvc")) { Stop-Service -Name $svc -Force }
            $suffix = "neooptimize_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss")
            $softwareDistribution = Join-Path $env:WINDIR "SoftwareDistribution"
            $catroot2 = Join-Path $env:WINDIR "System32\catroot2"
            if (Test-Path $softwareDistribution) { Rename-Item -Path $softwareDistribution -NewName ("SoftwareDistribution.{0}" -f $suffix) }
            if (Test-Path $catroot2) { Rename-Item -Path $catroot2 -NewName ("catroot2.{0}" -f $suffix) }
            foreach ($svc in @("cryptsvc", "bits", "wuauserv")) { Start-Service -Name $svc }
            Write-OK "Windows Update components reset requested. Reboot Windows before retrying updates."
        }
    }
}

Write-Footer
Wait-AnyKey
