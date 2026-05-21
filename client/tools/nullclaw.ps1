#Requires -Version 5.1
<#
.SYNOPSIS
    NullClaw local bridge for NeoOptimize.

.DESCRIPTION
    Read-only compatibility operator used when a dedicated NullClaw CLI is not
    installed. It provides status, doctor, and agent responses for NEO while
    collecting only local system posture metadata.
#>

param(
    [Parameter(Position = 0)]
    [string]$Command = "status",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Remaining
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"

function Get-BridgeSnapshot {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
    $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
    $firewall = Get-NetFirewallProfile -ErrorAction SilentlyContinue
    $computerName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [Environment]::MachineName }
    $disabledFirewallProfiles = @($firewall | Where-Object { $_ -and -not $_.Enabled } | ForEach-Object { $_.Name })
    $services = @("WinDefend", "MpsSvc", "wuauserv", "bits", "cryptsvc", "Winmgmt", "EventLog", "Schedule") | ForEach-Object {
        $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            name = $_
            status = if ($svc) { [string]$svc.Status } else { "Missing" }
        }
    }

    [PSCustomObject]@{
        computer = $computerName
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        bridge = "nullclaw-local-bridge"
        mode = "read_only"
        os = [PSCustomObject]@{
            name = $os.Caption
            version = $os.Version
            build = $os.BuildNumber
            architecture = $os.OSArchitecture
        }
        hardware = [PSCustomObject]@{
            manufacturer = $cs.Manufacturer
            model = $cs.Model
            ram_gb = if ($cs.TotalPhysicalMemory) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 2) } else { $null }
        }
        disk = [PSCustomObject]@{
            c_free_gb = if ($disk.FreeSpace) { [math]::Round($disk.FreeSpace / 1GB, 2) } else { $null }
            c_free_percent = if ($disk.Size) { [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1) } else { $null }
        }
        security = [PSCustomObject]@{
            defender_realtime = $defender.RealTimeProtectionEnabled
            defender_signature_age_days = $defender.AntivirusSignatureAge
            firewall_disabled_profiles = @($disabledFirewallProfiles)
        }
        services = @($services)
    }
}

function Get-RiskSignals {
    param($Snapshot)

    $signals = New-Object System.Collections.Generic.List[string]
    if ($Snapshot.security.defender_realtime -eq $false) { $signals.Add("Defender realtime protection is disabled.") | Out-Null }
    if (@($Snapshot.security.firewall_disabled_profiles).Count -gt 0) { $signals.Add("Firewall disabled profiles: $(@($Snapshot.security.firewall_disabled_profiles) -join ', ').") | Out-Null }
    if ($Snapshot.disk.c_free_percent -ne $null -and $Snapshot.disk.c_free_percent -lt 10) { $signals.Add("C: disk free space is below 10%.") | Out-Null }
    $stoppedCritical = @($Snapshot.services | Where-Object { $_.status -eq "Stopped" -and $_.name -notin @("wuauserv", "bits") })
    if ($stoppedCritical.Count -gt 0) { $signals.Add("Critical service stopped: $(@($stoppedCritical.name) -join ', ').") | Out-Null }
    if ($signals.Count -eq 0) { $signals.Add("No critical local security signal detected by NullClaw bridge.") | Out-Null }
    return @($signals)
}

function Write-Status {
    $snapshot = Get-BridgeSnapshot
    [PSCustomObject]@{
        connected = $true
        cli = "nullclaw-local-bridge"
        mode = "read_only"
        version = "0.1.0"
        computer = $snapshot.computer
        status = "ready"
        secret_policy = "no secrets collected"
    } | ConvertTo-Json -Depth 5
}

function Write-Doctor {
    $snapshot = Get-BridgeSnapshot
    $signals = Get-RiskSignals -Snapshot $snapshot
    [PSCustomObject]@{
        provider = "NullClaw Local Bridge"
        status = "ready"
        mode = "read_only"
        signals = @($signals)
        recommended_command = if (($signals -join " ") -match "Defender|Firewall") { "SECURITY_SCAN" } else { "SYSTEM_DIAGNOSTICS" }
        confidence = 0.72
        snapshot = $snapshot
    } | ConvertTo-Json -Depth 8
}

function Write-AgentResponse {
    param([string]$Prompt)

    $snapshot = Get-BridgeSnapshot
    $signals = Get-RiskSignals -Snapshot $snapshot
    $command = if (($signals -join " ") -match "Defender|Firewall") { "SECURITY_SCAN" } elseif (($signals -join " ") -match "disk") { "DEEP_SCAN" } else { "SYSTEM_DIAGNOSTICS" }
@"
Provider: NullClaw Local Bridge
Mode: read-only operator hand

# NullClaw Assessment

Prompt:
$Prompt

Signals:
$(@($signals | ForEach-Object { "- $_" }) -join "`r`n")

Recommended RMM command: $command
Confidence: 72%

Safety:
- No secrets, camera, microphone, documents, or credentials were collected.
- This bridge does not execute remediation. It only returns an operator recommendation to NEO/RMM.
"@
}

$normalized = $Command.Trim().ToLowerInvariant()
switch ($normalized) {
    "status" { Write-Status; exit 0 }
    "doctor" { Write-Doctor; exit 0 }
    "agent" {
        $prompt = (@($Remaining) -join " ")
        if ($prompt -match '(^|\s)-m\s+(.+)$') { $prompt = $Matches[2] }
        Write-AgentResponse -Prompt $prompt
        exit 0
    }
    "onboard" {
        Write-Host "NullClaw Local Bridge is already available in read-only compatibility mode."
        exit 0
    }
    default {
        Write-Error "Unknown NullClaw bridge command: $Command"
        exit 2
    }
}
