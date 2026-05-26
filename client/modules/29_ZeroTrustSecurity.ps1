#Requires -RunAsAdministrator
<# MODULE 29 - ZERO-TRUST SECURITY #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "29" "ZT" "ZERO-TRUST SECURITY"

$asrRules = @(
    [PSCustomObject]@{ Id="56a863a9-875e-4185-98a7-b882c64b5ce5"; Name="Block abuse of exploited vulnerable signed drivers" },
    [PSCustomObject]@{ Id="9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2"; Name="Block credential stealing from LSASS" },
    [PSCustomObject]@{ Id="be9ba2d9-53ea-4cdc-84e5-9b1eeee46550"; Name="Block executable content from email and webmail" },
    [PSCustomObject]@{ Id="d4f940ab-401b-4efc-aadc-ad5f3c50688a"; Name="Block Office child processes" },
    [PSCustomObject]@{ Id="d3e037e1-3eb8-44c8-a917-57927947596d"; Name="Block JavaScript/VBScript downloaded executables" }
)

function Get-NeoRegValue {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

$mpStatus = Get-MpComputerStatus
$mpPref = Get-MpPreference
$smb1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol
$firewallProfiles = @(Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction)
$lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$vbsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
$hvciPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"

$report = [PSCustomObject]@{
    captured_at = (Get-Date).ToString("o")
    defender = $mpStatus | Select-Object AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, BehaviorMonitorEnabled, IoavProtectionEnabled, NISEnabled
    defender_preferences = $mpPref | Select-Object EnableControlledFolderAccess, EnableNetworkProtection, AttackSurfaceReductionRules_Ids, AttackSurfaceReductionRules_Actions
    firewall = $firewallProfiles
    smb1_state = $smb1.State
    lsa_run_as_ppl = Get-NeoRegValue $lsaPath "RunAsPPL"
    vbs_enable = Get-NeoRegValue $vbsPath "EnableVirtualizationBasedSecurity"
    hvci_enable = Get-NeoRegValue $hvciPath "Enabled"
}

Write-Step "SECURITY POSTURE"
Write-Host ""
Write-Info ("Defender realtime     : {0}" -f $mpStatus.RealTimeProtectionEnabled)
Write-Info ("Firewall profiles     : {0}" -f (($firewallProfiles | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ", "))
Write-Info ("SMBv1 optional feature: {0}" -f $report.smb1_state)
Write-Info ("LSA RunAsPPL          : {0}" -f $(if ($null -eq $report.lsa_run_as_ppl) { "not configured" } else { $report.lsa_run_as_ppl }))
Write-Info ("VBS policy            : {0}" -f $(if ($null -eq $report.vbs_enable) { "not configured" } else { $report.vbs_enable }))
Write-Info ("HVCI policy           : {0}" -f $(if ($null -eq $report.hvci_enable) { "not configured" } else { $report.hvci_enable }))

$dir = Join-Path $Global:LogDir "security"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$path = Join-Path $dir ("zero-trust_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
Write-OK "Zero-Trust report: $path"

if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) {
    Write-Warn "Non-interactive mode: audit only."
    Wait-AnyKey
    return
}

Write-Host ""
Write-Host "  [1] Audit only"
Write-Host "  [2] Add recommended ASR rules in AuditMode"
Write-Host "  [3] Enforce core hardening (SMBv1 off, LSA protection, ASR block)"
Write-Host ""
$choice = Read-NeoChoice "  Pilihan [1-3]" @("1","2","3") "1"

if ($choice -eq "2") {
    $ids = @($asrRules | Select-Object -ExpandProperty Id)
    $actions = @($ids | ForEach-Object { "AuditMode" })
    if (Confirm-NeoAction "Add recommended ASR rules in AuditMode?" $false) {
        Add-MpPreference -AttackSurfaceReductionRules_Ids $ids -AttackSurfaceReductionRules_Actions $actions
        Write-OK "ASR audit rules added without overwriting existing rules."
    }
}

if ($choice -eq "3") {
    if (Test-NeoHighRiskConsent -ActionName "ZeroTrustSecurityEnforce" -RiskLevel "High" -Reason "Hardening dapat memblokir driver legacy, protokol lama, atau aplikasi lama. Reboot mungkin diperlukan.") {
        if (Confirm-NeoAction "Disable SMBv1 optional feature?" $false) {
            Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart | Out-Null
            Write-OK "SMBv1 disable requested."
        }
        if (Confirm-NeoAction "Enable LSA protection RunAsPPL?" $false) {
            Backup-RegKey $lsaPath | Out-Null
            Set-Reg $lsaPath "RunAsPPL" 1
            Write-OK "LSA protection policy set. Reboot required."
        }
        if (Confirm-NeoAction "Set recommended ASR rules to block mode?" $false) {
            $ids = @($asrRules | Select-Object -ExpandProperty Id)
            $actions = @($ids | ForEach-Object { "Enabled" })
            Add-MpPreference -AttackSurfaceReductionRules_Ids $ids -AttackSurfaceReductionRules_Actions $actions
            Write-OK "ASR block rules added."
        }
    }
}

Write-Footer
Wait-AnyKey
