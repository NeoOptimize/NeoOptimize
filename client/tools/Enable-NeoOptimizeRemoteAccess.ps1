#Requires -Version 5.1
<#
.SYNOPSIS
    Optional remote-access bootstrap for authorized NeoOptimize administrators.
.DESCRIPTION
    Reports or enables WinRM, OpenSSH Server, and QEMU Guest Agent readiness.
    This tool is intentionally dry-run by default. Use -Apply from an elevated
    console to make changes. Public builds do not enable remote access silently
    and do not bundle QEMU/SPICE guest tools.
#>

param(
    [ValidateSet("Status", "WinRM", "OpenSSH", "QemuGuestAgent", "All", "Disable")]
    [string]$Mode = "Status",

    [switch]$Apply,
    [switch]$LabAllowBasic,
    [switch]$NoPrompt,

    [string]$AllowedRemoteAddress = "",
    [string]$QemuGuestAgentInstallerPath = "",
    [string]$QemuGuestAgentInstallerArgs = ""
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$Script:Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Script:ConfigPath = Join-Path $Script:Root "config\NeoOptimize.RemoteAccess.json"

function Test-NeoAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Read-NeoRemoteAccessConfig {
    $fallback = [PSCustomObject]@{
        audit_log = "logs\remote_access_bootstrap.jsonl"
        allowed_remote_addresses_default = "LocalSubnet"
        winrm = [PSCustomObject]@{
            allow_basic = $false
            allow_unencrypted = $false
            firewall_remote_addresses = @("LocalSubnet")
            trusted_hosts = @()
        }
        openssh = [PSCustomObject]@{
            install_capability = $true
            firewall_remote_addresses = @("LocalSubnet")
            password_authentication = "preserve"
            pubkey_authentication = $true
        }
        qemu_guest_agent = [PSCustomObject]@{
            start_if_installed = $true
            installer_path = ""
            installer_args = ""
            public_bundle = $false
        }
    }

    if (-not (Test-Path $Script:ConfigPath)) { return $fallback }
    try {
        $cfg = Get-Content -Path $Script:ConfigPath -Raw | ConvertFrom-Json
        if (-not $cfg.audit_log) { $cfg | Add-Member -NotePropertyName audit_log -NotePropertyValue $fallback.audit_log -Force }
        if (-not $cfg.allowed_remote_addresses_default) { $cfg | Add-Member -NotePropertyName allowed_remote_addresses_default -NotePropertyValue $fallback.allowed_remote_addresses_default -Force }
        if (-not $cfg.winrm) { $cfg | Add-Member -NotePropertyName winrm -NotePropertyValue $fallback.winrm -Force }
        if (-not $cfg.openssh) { $cfg | Add-Member -NotePropertyName openssh -NotePropertyValue $fallback.openssh -Force }
        if (-not $cfg.qemu_guest_agent) { $cfg | Add-Member -NotePropertyName qemu_guest_agent -NotePropertyValue $fallback.qemu_guest_agent -Force }
        return $cfg
    } catch {
        return $fallback
    }
}

$Script:Config = Read-NeoRemoteAccessConfig
$Script:AuditPath = Join-Path $Script:Root ([string]$Script:Config.audit_log)
$Script:Results = [System.Collections.Generic.List[object]]::new()

function Write-NeoAudit {
    param(
        [string]$Action,
        [string]$Status,
        [object]$Details = $null
    )
    try {
        $dir = Split-Path -Parent $Script:AuditPath
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
        $entry = [ordered]@{
            timestamp = (Get-Date).ToString("o")
            mode = $Mode
            apply = [bool]$Apply
            lab_allow_basic = [bool]$LabAllowBasic
            action = $Action
            status = $Status
            details = $Details
        }
        Add-Content -Path $Script:AuditPath -Value ($entry | ConvertTo-Json -Compress -Depth 8)
    } catch {
        Write-Verbose $_.Exception.Message
    }
}

function Add-NeoResult {
    param(
        [string]$Component,
        [string]$Action,
        [string]$Status,
        [object]$Details = $null
    )
    $item = [ordered]@{
        component = $Component
        action = $Action
        status = $Status
        details = $Details
    }
    $Script:Results.Add([PSCustomObject]$item) | Out-Null
    Write-NeoAudit -Action "$Component.$Action" -Status $Status -Details $Details
}

function Get-ConfigArrayValue {
    param($Object, [string]$Name, [string[]]$Fallback)
    try {
        if ($Object -and $Object.$Name) {
            return @($Object.$Name)
        }
    } catch {
        Write-Verbose $_.Exception.Message
    }
    return @($Fallback)
}

function Resolve-AllowedRemoteAddress {
    if (-not [string]::IsNullOrWhiteSpace($AllowedRemoteAddress)) {
        return $AllowedRemoteAddress.Trim()
    }
    $winrmAddr = Get-ConfigArrayValue $Script:Config.winrm "firewall_remote_addresses" @([string]$Script:Config.allowed_remote_addresses_default)
    if ($winrmAddr.Count -gt 0) { return ($winrmAddr -join ",") }
    return "LocalSubnet"
}

function Test-AllowedRemoteAddress {
    param([string]$RemoteAddress)
    if ([string]::IsNullOrWhiteSpace($RemoteAddress)) { return $false }
    if ($RemoteAddress -match '(?i)(^|,|\s)(any|\*)(,|\s|$)') { return $false }
    if ($RemoteAddress -match '(^|,|\s)0\.0\.0\.0/0(,|\s|$)') { return $false }
    if ($RemoteAddress -match '(^|,|\s)::/0(,|\s|$)') { return $false }
    return $true
}

function Invoke-NeoChange {
    param(
        [string]$Component,
        [string]$Action,
        [scriptblock]$ScriptBlock,
        [object]$DryRunDetails = $null
    )

    if (-not $Apply) {
        Add-NeoResult $Component $Action "dry_run" $DryRunDetails
        return $null
    }

    try {
        $value = & $ScriptBlock
        Add-NeoResult $Component $Action "ok" $value
        return $value
    } catch {
        Add-NeoResult $Component $Action "error" $_.Exception.Message
        return $null
    }
}

function Get-ServiceSnapshot {
    param([string[]]$Names)
    $items = @()
    foreach ($name in $Names) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) {
            $items += [ordered]@{
                name = $svc.Name
                display_name = $svc.DisplayName
                status = [string]$svc.Status
                start_type = [string]$svc.StartType
            }
        }
    }
    return $items
}

function Get-WinRMStatus {
    $svc = Get-Service -Name WinRM -ErrorAction SilentlyContinue
    $listenerText = ""
    try { $listenerText = (winrm enumerate winrm/config/listener 2>&1 | Out-String).Trim() } catch { $listenerText = $_.Exception.Message }
    $authBasic = $null
    $allowUnencrypted = $null
    try { $authBasic = (Get-Item -Path WSMan:\localhost\Service\Auth\Basic -ErrorAction SilentlyContinue).Value } catch {}
    try { $allowUnencrypted = (Get-Item -Path WSMan:\localhost\Service\AllowUnencrypted -ErrorAction SilentlyContinue).Value } catch {}

    return [ordered]@{
        service = if ($svc) { [string]$svc.Status } else { "not_found" }
        start_type = if ($svc) { [string]$svc.StartType } else { "unknown" }
        listener_present = ($listenerText -match "Transport")
        basic_auth = $authBasic
        allow_unencrypted = $allowUnencrypted
        listener_summary = ($listenerText -replace '\s+', ' ').Substring(0, [Math]::Min(260, ($listenerText -replace '\s+', ' ').Length))
    }
}

function Enable-NeoWinRM {
    $remoteAddress = Resolve-AllowedRemoteAddress
    if (-not (Test-AllowedRemoteAddress $remoteAddress)) {
        Add-NeoResult "winrm" "scope_check" "blocked" "RemoteAddress '$remoteAddress' is too broad. Use LocalSubnet or a specific private CIDR."
        return
    }

    Invoke-NeoChange "winrm" "enable_psremoting" {
        Enable-PSRemoting -SkipNetworkProfileCheck -Force | Out-Null
        Set-Service -Name WinRM -StartupType Automatic
        Start-Service -Name WinRM
        "WinRM service enabled"
    } @{ remote_address = $remoteAddress }

    Invoke-NeoChange "winrm" "firewall_scope" {
        $rules = @(Get-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue)
        if ($rules.Count -gt 0) {
            $rules | Set-NetFirewallRule -Enabled True -RemoteAddress $remoteAddress | Out-Null
        } else {
            New-NetFirewallRule -Name "NeoOptimize-WinRM-HTTP-In" -DisplayName "NeoOptimize WinRM HTTP (Scoped)" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -RemoteAddress $remoteAddress | Out-Null
        }
        "WinRM firewall scoped to $remoteAddress"
    } @{ remote_address = $remoteAddress }

    Invoke-NeoChange "winrm" "secure_defaults" {
        if ($LabAllowBasic) {
            Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true -Force
            Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true -Force
            "LAB MODE: Basic authentication and unencrypted transport enabled by explicit request"
        } else {
            Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false -Force
            Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false -Force
            "Basic authentication and unencrypted transport disabled"
        }
    } @{ lab_allow_basic = [bool]$LabAllowBasic }

    $trustedHosts = Get-ConfigArrayValue $Script:Config.winrm "trusted_hosts" @()
    if ($trustedHosts.Count -gt 0 -and $Apply) {
        try {
            Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value ($trustedHosts -join ",") -Force
            Add-NeoResult "winrm" "trusted_hosts" "ok" "Configured outgoing TrustedHosts from policy"
        } catch {
            Add-NeoResult "winrm" "trusted_hosts" "error" $_.Exception.Message
        }
    } elseif ($trustedHosts.Count -gt 0) {
        Add-NeoResult "winrm" "trusted_hosts" "dry_run" "Would configure outgoing TrustedHosts from policy"
    }
}

function Get-OpenSSHStatus {
    $sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue
    $capability = $null
    try {
        $capability = Get-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" -ErrorAction SilentlyContinue
    } catch {
        $capability = $null
    }

    return [ordered]@{
        capability_state = if ($capability) { [string]$capability.State } else { "unknown" }
        service = if ($sshd) { [string]$sshd.Status } else { "not_found" }
        start_type = if ($sshd) { [string]$sshd.StartType } else { "unknown" }
        firewall_rule = [bool](Get-NetFirewallRule -Name "NeoOptimize-OpenSSH-Inbound" -ErrorAction SilentlyContinue)
    }
}

function Set-SshdConfigOption {
    param([string]$Name, [string]$Value)
    $path = Join-Path $env:ProgramData "ssh\sshd_config"
    if (-not (Test-Path $path)) {
        Add-NeoResult "openssh" "sshd_config_$Name" "skipped" "sshd_config not found"
        return
    }

    if (-not $Apply) {
        Add-NeoResult "openssh" "sshd_config_$Name" "dry_run" "$Name $Value"
        return
    }

    try {
        $content = Get-Content -Path $path -ErrorAction Stop
        Copy-Item -Path $path -Destination "$path.neooptimize.bak" -Force
        $pattern = "^\s*#?\s*$([regex]::Escape($Name))\s+"
        $replacement = "$Name $Value"
        $changed = $false
        $newContent = @()
        foreach ($line in $content) {
            if ($line -match $pattern) {
                if (-not $changed) {
                    $newContent += $replacement
                    $changed = $true
                }
            } else {
                $newContent += $line
            }
        }
        if (-not $changed) { $newContent += $replacement }
        Set-Content -Path $path -Value $newContent -Encoding ASCII
        Add-NeoResult "openssh" "sshd_config_$Name" "ok" $replacement
    } catch {
        Add-NeoResult "openssh" "sshd_config_$Name" "error" $_.Exception.Message
    }
}

function Enable-NeoOpenSSH {
    $remoteAddress = Resolve-AllowedRemoteAddress
    $sshAddr = Get-ConfigArrayValue $Script:Config.openssh "firewall_remote_addresses" @($remoteAddress)
    if ($sshAddr.Count -gt 0) { $remoteAddress = ($sshAddr -join ",") }

    if (-not (Test-AllowedRemoteAddress $remoteAddress)) {
        Add-NeoResult "openssh" "scope_check" "blocked" "RemoteAddress '$remoteAddress' is too broad. Use LocalSubnet or a specific private CIDR."
        return
    }

    $status = Get-OpenSSHStatus
    if ($status.capability_state -ne "Installed") {
        $installCapability = $true
        try { $installCapability = [bool]$Script:Config.openssh.install_capability } catch {}
        if ($installCapability) {
            Invoke-NeoChange "openssh" "install_capability" {
                Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" | Out-Null
                "OpenSSH Server capability installed"
            } @{ capability = "OpenSSH.Server~~~~0.0.1.0" }
        } else {
            Add-NeoResult "openssh" "install_capability" "skipped" "Policy disables capability installation"
        }
    }

    Invoke-NeoChange "openssh" "start_service" {
        Set-Service -Name sshd -StartupType Automatic
        Start-Service -Name sshd
        "sshd service started"
    } $status

    Invoke-NeoChange "openssh" "firewall_scope" {
        $existing = Get-NetFirewallRule -Name "NeoOptimize-OpenSSH-Inbound" -ErrorAction SilentlyContinue
        if ($existing) {
            Set-NetFirewallRule -Name "NeoOptimize-OpenSSH-Inbound" -Enabled True -RemoteAddress $remoteAddress | Out-Null
        } else {
            New-NetFirewallRule -Name "NeoOptimize-OpenSSH-Inbound" -DisplayName "NeoOptimize OpenSSH Server (Scoped)" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -RemoteAddress $remoteAddress | Out-Null
        }
        "OpenSSH firewall scoped to $remoteAddress"
    } @{ remote_address = $remoteAddress }

    try {
        if ([bool]$Script:Config.openssh.pubkey_authentication) {
            Set-SshdConfigOption -Name "PubkeyAuthentication" -Value "yes"
        }
        $passwordMode = [string]$Script:Config.openssh.password_authentication
        if ($passwordMode -match '^(true|false)$') {
            Set-SshdConfigOption -Name "PasswordAuthentication" -Value ($(if ($passwordMode -eq "true") { "yes" } else { "no" }))
        } else {
            Add-NeoResult "openssh" "password_authentication" "preserved" "Policy keeps existing sshd password authentication setting"
        }
    } catch {
        Add-NeoResult "openssh" "sshd_config" "error" $_.Exception.Message
    }

    if ($Apply) {
        Restart-Service -Name sshd -ErrorAction SilentlyContinue
    }
}

function Get-QemuGuestAgentStatus {
    $services = @("QEMU-GA", "qemu-ga", "QemuGuestAgent")
    $svc = $null
    foreach ($name in $services) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) { break }
    }
    return [ordered]@{
        service = if ($svc) { $svc.Name } else { "not_found" }
        status = if ($svc) { [string]$svc.Status } else { "not_found" }
        start_type = if ($svc) { [string]$svc.StartType } else { "unknown" }
        public_bundle = $false
    }
}

function Enable-NeoQemuGuestAgent {
    $status = Get-QemuGuestAgentStatus
    if ($status.service -ne "not_found") {
        Invoke-NeoChange "qemu_guest_agent" "start_service" {
            Set-Service -Name $status.service -StartupType Automatic
            Start-Service -Name $status.service
            "QEMU Guest Agent service started"
        } $status
        return
    }

    $installer = $QemuGuestAgentInstallerPath
    if ([string]::IsNullOrWhiteSpace($installer)) {
        try { $installer = [string]$Script:Config.qemu_guest_agent.installer_path } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($installer) -or -not (Test-Path $installer)) {
        Add-NeoResult "qemu_guest_agent" "install" "installer_required" "QEMU Guest Agent is not bundled. Provide -QemuGuestAgentInstallerPath for lab VM installation."
        return
    }

    $args = $QemuGuestAgentInstallerArgs
    if ([string]::IsNullOrWhiteSpace($args)) {
        try { $args = [string]$Script:Config.qemu_guest_agent.installer_args } catch {}
    }

    Invoke-NeoChange "qemu_guest_agent" "install_local_package" {
        $ext = [System.IO.Path]::GetExtension($installer).ToLowerInvariant()
        if ($ext -eq ".msi") {
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$installer`" /qn /norestart" -Wait -WindowStyle Hidden
        } elseif (-not [string]::IsNullOrWhiteSpace($args)) {
            Start-Process -FilePath $installer -ArgumentList $args -Wait
        } else {
            throw "EXE installer requires explicit -QemuGuestAgentInstallerArgs because silent switches vary by package."
        }
        "Local QEMU Guest Agent installer executed"
    } @{ installer = $installer; args = $args }
}

function Disable-NeoRemoteAccess {
    Invoke-NeoChange "winrm" "disable_service" {
        Stop-Service -Name WinRM -Force -ErrorAction SilentlyContinue
        Set-Service -Name WinRM -StartupType Manual -ErrorAction SilentlyContinue
        "WinRM stopped and set to Manual"
    } (Get-WinRMStatus)

    Invoke-NeoChange "openssh" "disable_service" {
        Disable-NetFirewallRule -Name "NeoOptimize-OpenSSH-Inbound" -ErrorAction SilentlyContinue
        Stop-Service -Name sshd -Force -ErrorAction SilentlyContinue
        Set-Service -Name sshd -StartupType Manual -ErrorAction SilentlyContinue
        "NeoOptimize OpenSSH firewall rule disabled; sshd stopped and set to Manual"
    } (Get-OpenSSHStatus)

    Invoke-NeoChange "qemu_guest_agent" "disable_service" {
        $status = Get-QemuGuestAgentStatus
        if ($status.service -ne "not_found") {
            Stop-Service -Name $status.service -Force -ErrorAction SilentlyContinue
            Set-Service -Name $status.service -StartupType Manual -ErrorAction SilentlyContinue
            return "QEMU Guest Agent stopped and set to Manual"
        }
        "QEMU Guest Agent not installed"
    } (Get-QemuGuestAgentStatus)
}

function Show-NeoStatus {
    Add-NeoResult "system" "admin" ($(if (Test-NeoAdmin) { "ok" } else { "warning" })) @{ is_admin = (Test-NeoAdmin) }
    Add-NeoResult "winrm" "status" "observed" (Get-WinRMStatus)
    Add-NeoResult "openssh" "status" "observed" (Get-OpenSSHStatus)
    Add-NeoResult "qemu_guest_agent" "status" "observed" (Get-QemuGuestAgentStatus)
}

if (-not (Test-NeoAdmin)) {
    Add-NeoResult "system" "admin_check" "blocked" "Run as Administrator is required."
    [PSCustomObject][ordered]@{
        schema_version = "1.0"
        mode = $Mode
        apply = [bool]$Apply
        allowed_remote_address = $AllowedRemoteAddress
        status = "blocked"
        results = @($Script:Results)
    } | ConvertTo-Json -Depth 8
    exit 1
}

$resolvedAddress = Resolve-AllowedRemoteAddress
if (-not (Test-AllowedRemoteAddress $resolvedAddress)) {
    Add-NeoResult "system" "remote_scope" "blocked" "RemoteAddress '$resolvedAddress' is too broad. NeoOptimize blocks Any, *, 0.0.0.0/0, and ::/0."
    [PSCustomObject][ordered]@{
        schema_version = "1.0"
        mode = $Mode
        apply = [bool]$Apply
        allowed_remote_address = $resolvedAddress
        status = "blocked"
        results = @($Script:Results)
    } | ConvertTo-Json -Depth 8
    exit 2
}

if ($Apply -and -not $NoPrompt) {
    Write-Host ""
    Write-Host "NeoOptimize Remote Access Bootstrap" -ForegroundColor Cyan
    Write-Host "Mode: $Mode"
    Write-Host "Remote scope: $resolvedAddress"
    Write-Host "This can expose remote administration services. Continue? [y/N] " -NoNewline -ForegroundColor Yellow
    $answer = Read-Host
    if ($answer -notmatch '^(y|yes)$') {
        Add-NeoResult "system" "operator_consent" "cancelled" "Operator declined remote access change."
        [PSCustomObject][ordered]@{
            schema_version = "1.0"
            mode = $Mode
            apply = [bool]$Apply
            allowed_remote_address = $resolvedAddress
            status = "cancelled"
            results = @($Script:Results)
        } | ConvertTo-Json -Depth 8
        exit 3
    }
}

switch ($Mode) {
    "Status" { Show-NeoStatus }
    "WinRM" { Show-NeoStatus; Enable-NeoWinRM; Add-NeoResult "winrm" "post_status" "observed" (Get-WinRMStatus) }
    "OpenSSH" { Show-NeoStatus; Enable-NeoOpenSSH; Add-NeoResult "openssh" "post_status" "observed" (Get-OpenSSHStatus) }
    "QemuGuestAgent" { Show-NeoStatus; Enable-NeoQemuGuestAgent; Add-NeoResult "qemu_guest_agent" "post_status" "observed" (Get-QemuGuestAgentStatus) }
    "All" {
        Show-NeoStatus
        Enable-NeoWinRM
        Enable-NeoOpenSSH
        Enable-NeoQemuGuestAgent
        Add-NeoResult "winrm" "post_status" "observed" (Get-WinRMStatus)
        Add-NeoResult "openssh" "post_status" "observed" (Get-OpenSSHStatus)
        Add-NeoResult "qemu_guest_agent" "post_status" "observed" (Get-QemuGuestAgentStatus)
    }
    "Disable" { Show-NeoStatus; Disable-NeoRemoteAccess; Show-NeoStatus }
}

$hasBlocked = @($Script:Results | Where-Object { $_.status -eq "blocked" }).Count -gt 0
$hasError = @($Script:Results | Where-Object { $_.status -eq "error" }).Count -gt 0
$summaryStatus = if ($hasBlocked) { "blocked" } elseif ($hasError) { "error" } elseif (-not $Apply -and $Mode -ne "Status") { "dry_run" } else { "ok" }

[PSCustomObject][ordered]@{
    schema_version = "1.0"
    generated_at = (Get-Date).ToString("o")
    mode = $Mode
    apply = [bool]$Apply
    lab_allow_basic = [bool]$LabAllowBasic
    allowed_remote_address = $resolvedAddress
    status = $summaryStatus
    audit_log = $Script:AuditPath
    public_bundle_qemu_guest_agent = $false
    results = @($Script:Results)
} | ConvertTo-Json -Depth 10
