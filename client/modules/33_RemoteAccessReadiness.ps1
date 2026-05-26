#Requires -RunAsAdministrator
<# MODULE 33 - REMOTE ACCESS READINESS CHECK #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "33" "RMT" "REMOTE ACCESS READINESS CHECK"

function Get-NeoRegValue {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

$winrm = Get-Service WinRM
$sshd = Get-Service sshd
$qga = Get-Service QEMU-GA
$rdpDeny = Get-NeoRegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" "fDenyTSConnections"
$listeners = & winrm.exe enumerate winrm/config/listener 2>&1
$rmmConfigPath = Join-Path $Global:NeoOptimizeRoot "config\NeoOptimize.RMM.json"
$rmmConfig = if (Test-Path $rmmConfigPath) { Get-Content -Path $rmmConfigPath -Raw | ConvertFrom-Json } else { $null }

$report = [PSCustomObject]@{
    captured_at = (Get-Date).ToString("o")
    winrm_service = $winrm | Select-Object Name, Status, StartType
    sshd_service = $sshd | Select-Object Name, Status, StartType
    qemu_guest_agent = $qga | Select-Object Name, Status, StartType
    rdp_fdenytsconnections = $rdpDeny
    winrm_listeners = $listeners
    firewall = [PSCustomObject]@{
        winrm = @(Get-NetFirewallRule -DisplayGroup "Windows Remote Management" | Select-Object DisplayName, Enabled, Profile, Direction, Action)
        openssh = @(Get-NetFirewallRule | Where-Object { $_.DisplayName -match "OpenSSH|SSH" } | Select-Object DisplayName, Enabled, Profile, Direction, Action)
        rdp = @(Get-NetFirewallRule -DisplayGroup "Remote Desktop" | Select-Object DisplayName, Enabled, Profile, Direction, Action)
    }
    rmm = if ($rmmConfig) {
        [PSCustomObject]@{
            configured = $true
            dispatch_to_online_agents = $rmmConfig.dispatch_to_online_agents
            candidate_server_urls = $rmmConfig.candidate_server_urls
        }
    } else {
        [PSCustomObject]@{ configured = $false }
    }
}

Write-Step "REMOTE ACCESS POSTURE"
Write-Host ""
Write-Info ("WinRM service       : {0} / {1}" -f $winrm.Status, $winrm.StartType)
Write-Info ("OpenSSH service     : {0} / {1}" -f $(if ($sshd) { $sshd.Status } else { "NotInstalled" }), $(if ($sshd) { $sshd.StartType } else { "N/A" }))
Write-Info ("QEMU Guest Agent    : {0} / {1}" -f $(if ($qga) { $qga.Status } else { "NotInstalled" }), $(if ($qga) { $qga.StartType } else { "N/A" }))
Write-Info ("RDP deny flag       : {0}" -f $(if ($null -eq $rdpDeny) { "not configured" } else { $rdpDeny }))
Write-Info ("RMM config present  : {0}" -f [bool]$rmmConfig)
Write-Warn "This module is read-only. It does not enable WinRM, RDP, OpenSSH, RemoteRegistry, ports, or TrustedHosts."

$dir = Join-Path $Global:LogDir "remote"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$path = Join-Path $dir ("remote-readiness_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
Write-OK "Remote readiness report: $path"
Write-Footer
Wait-AnyKey
