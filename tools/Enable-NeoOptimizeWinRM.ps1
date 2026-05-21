#Requires -RunAsAdministrator
<#
.SYNOPSIS
    One-time Windows VM bootstrap for NeoOptimize lab deployment over WinRM.

.DESCRIPTION
    Run this script inside the Windows VM from an elevated PowerShell session.
    The default path enables WinRM and restricts inbound firewall traffic to the
    supplied host address. Basic-over-HTTP is disabled by default; enable it only
    for an isolated lab network.
#>

param(
    [string]$HostAddress = "192.168.122.1",
    [switch]$AllowBasicHttpForLab,
    [switch]$SkipNetworkProfileCheck
)

$ErrorActionPreference = "Stop"

Write-Host "[NeoOptimize] Enabling WinRM for lab deployment..."

try {
    Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq "Public" } |
        Set-NetConnectionProfile -NetworkCategory Private -ErrorAction Stop
} catch {
    Write-Warning "Could not switch all network profiles to Private: $($_.Exception.Message)"
}

try {
    if ($SkipNetworkProfileCheck) {
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
    } else {
        Enable-PSRemoting -Force
    }
} catch {
    Write-Warning "Enable-PSRemoting failed: $($_.Exception.Message)"
    Write-Host "Retrying with -SkipNetworkProfileCheck..."
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
}

Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM

$ruleName = "NeoOptimize Lab WinRM from Host"
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existingRule) {
    Remove-NetFirewallRule -DisplayName $ruleName
}

New-NetFirewallRule `
    -DisplayName $ruleName `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort 5985 `
    -RemoteAddress $HostAddress | Out-Null

if ($AllowBasicHttpForLab) {
    Write-Warning "Enabling Basic authentication and AllowUnencrypted for isolated lab use only."
    try {
        Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true -ErrorAction Stop
        Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true -ErrorAction Stop
    } catch {
        Write-Warning "Basic/AllowUnencrypted WinRM policy was not enabled: $($_.Exception.Message)"
        Write-Warning "This does not block local NeoOptimize Agent installation."
    }
} else {
    try {
        Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false -ErrorAction Stop
    } catch {
        Write-Warning "Could not enforce encrypted-only WinRM policy: $($_.Exception.Message)"
    }
}

$listeners = winrm enumerate winrm/config/listener
$serviceAuth = Get-ChildItem WSMan:\localhost\Service\Auth | Select-Object Name, Value

Write-Host "[NeoOptimize] WinRM ready."
Write-Host "[NeoOptimize] Allowed host: $HostAddress"
Write-Host "[NeoOptimize] Listener summary:"
$listeners
Write-Host "[NeoOptimize] Auth summary:"
$serviceAuth | Format-Table -AutoSize
