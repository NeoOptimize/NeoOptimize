#Requires -RunAsAdministrator
<#
.SYNOPSIS
    NeoOptimize permission and remote-access preflight.
.DESCRIPTION
    Audits administrator posture, UAC, WMI, performance counters, services, and
    remote-access readiness. This module intentionally does not suppress UAC,
    enable RDP/WinRM, set TrustedHosts, enable admin shares, or start RemoteRegistry.
#>

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "00" "PERM" "PERMISSIONS PREFLIGHT"

function Get-RegOrNull {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

$report = [ordered]@{
    timestamp = (Get-Date).ToString("s")
    computer = $env:COMPUTERNAME
    user = "$env:USERDOMAIN\$env:USERNAME"
    checks = @()
}

function Add-Check {
    param([string]$Name, [string]$Status, [string]$Detail)
    $report.checks += [PSCustomObject]@{ name = $Name; status = $Status; detail = $Detail }
    $color = switch ($Status) {
        "OK" { $Global:GREEN }
        "WARN" { $Global:YELLOW }
        "FAIL" { $Global:RED }
        default { $Global:CYAN }
    }
    Write-Host "  $color[$Status]$($Global:RESET) $Name - $Detail"
}

Write-Step "ELEVATION"
Write-Host ""
if (Test-IsAdmin) {
    Add-Check "Administrator token" "OK" "Process is elevated."
} else {
    Add-Check "Administrator token" "FAIL" "Run NeoOptimize as Administrator."
}

Write-Host ""
Write-Step "UAC POLICY"
Write-Host ""
$uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$enableLua = Get-RegOrNull $uacPath "EnableLUA"
$adminPrompt = Get-RegOrNull $uacPath "ConsentPromptBehaviorAdmin"
$secureDesktop = Get-RegOrNull $uacPath "PromptOnSecureDesktop"
Add-Check "EnableLUA" ($(if ($enableLua -eq 1) { "OK" } else { "WARN" })) "Current value: $enableLua"
Add-Check "ConsentPromptBehaviorAdmin" ($(if ($adminPrompt -eq 0) { "WARN" } else { "OK" })) "Current value: $adminPrompt"
Add-Check "PromptOnSecureDesktop" ($(if ($secureDesktop -eq 0) { "WARN" } else { "OK" })) "Current value: $secureDesktop"
Write-Info "NeoOptimize does not lower UAC settings. Elevation is handled by requireAdministrator manifests and RunAs prompts."

Write-Host ""
Write-Step "LOCAL MANAGEMENT SERVICES"
Write-Host ""
foreach ($name in @("Winmgmt", "Schedule", "EventLog", "PerfHost", "RemoteRegistry", "WinRM")) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc) {
        $status = if ($name -in @("RemoteRegistry", "WinRM") -and $svc.Status -eq "Running") { "WARN" } else { "OK" }
        Add-Check $name $status "Status=$($svc.Status); StartType=$($svc.StartType)"
    } else {
        Add-Check $name "WARN" "Service not found."
    }
}

Write-Host ""
Write-Step "REMOTE ACCESS POSTURE"
Write-Host ""
$rdpDeny = Get-RegOrNull "HKLM:\System\CurrentControlSet\Control\Terminal Server" "fDenyTSConnections"
$nla = Get-RegOrNull "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" "UserAuthentication"
Add-Check "RDP enabled" ($(if ($rdpDeny -eq 0) { "WARN" } else { "OK" })) "fDenyTSConnections=$rdpDeny; NLA=$nla"
try {
    $trustedHosts = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction Stop).Value
    Add-Check "WinRM TrustedHosts" ($(if ($trustedHosts -eq "*") { "WARN" } else { "OK" })) "Value='$trustedHosts'"
} catch {
    Add-Check "WinRM TrustedHosts" "INFO" "WSMan provider unavailable or WinRM not configured."
}
Write-Info "Use tools\Enable-NeoOptimizeRemoteAccess.ps1 for explicit remote-access planning/apply. This preflight does not open ports."

Write-Host ""
Write-Step "NEOOPTIMIZE SERVICE"
Write-Host ""
$svcName = "NeoOptimize RMM Agent"
$neoSvc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($neoSvc) {
    Add-Check $svcName "OK" "Status=$($neoSvc.Status); StartType=$($neoSvc.StartType)"
    if (Confirm-NeoAction "Configure service failure restart policy for NeoOptimize RMM Agent?" $false) {
        sc.exe failure "$svcName" reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null
        sc.exe failureflag "$svcName" 1 | Out-Null
        Write-OK "Service failure restart policy configured."
    }
} else {
    Add-Check $svcName "INFO" "Service not installed."
}

Write-Host ""
Write-Step "REPORT"
Write-Host ""
$dir = Join-Path $Global:LogDir "permissions"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$path = Join-Path $dir ("permissions-preflight_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$report | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding UTF8
Write-OK "Preflight report: $path"

Write-Host ""
Write-Separator "=" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)PERMISSIONS PREFLIGHT SELESAI$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
