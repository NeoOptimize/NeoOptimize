#Requires -RunAsAdministrator
<# MODULE 13 - ZERO-TRUST SECURITY & HARDENING #>
param([switch]$Enforce)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "13" "ZT" "ZERO-TRUST SECURITY"

$changes = 0
$canApply = [bool]$Enforce -or [bool]$Global:NeoOptimizeConfirmAll

function Invoke-ZeroTrustChange {
    param(
        [string]$Prompt,
        [scriptblock]$Action
    )
    if ($canApply -or (Confirm-NeoAction $Prompt $false)) {
        & $Action
        return $true
    }
    Write-Skip $Prompt
    return $false
}

Write-Step "DEVICE GUARD / HVCI AUDIT"
Write-Host ""
$dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
if ($dg) {
    Write-Info "SecurityServicesConfigured: $($dg.SecurityServicesConfigured -join ',')"
    Write-Info "SecurityServicesRunning: $($dg.SecurityServicesRunning -join ',')"
    Write-Info "VirtualizationBasedSecurityStatus: $($dg.VirtualizationBasedSecurityStatus)"
} else {
    Write-Info "DeviceGuard CIM class unavailable on this Windows edition/build."
}

if (Invoke-ZeroTrustChange "Enable VBS and HVCI? This can block incompatible drivers and requires reboot." {
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" "EnableVirtualizationBasedSecurity" 1 | Out-Null
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled" 1 | Out-Null
    Write-OK "VBS/HVCI registry policy enabled."
}) {
    $changes += 2
}

Write-Host ""
Write-Step "LEGACY PROTOCOL AUDIT"
Write-Host ""
$smb1 = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "SMB1" $null
$lm = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "LmCompatibilityLevel" $null
$llmnr = Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "EnableMulticast" $null
Write-Info "SMB1 registry value: $(if ($null -eq $smb1) { 'not configured' } else { $smb1 })"
Write-Info "LmCompatibilityLevel: $(if ($null -eq $lm) { 'not configured' } else { $lm })"
Write-Info "LLMNR EnableMulticast: $(if ($null -eq $llmnr) { 'not configured' } else { $llmnr })"

if (Invoke-ZeroTrustChange "Apply legacy protocol hardening: disable SMBv1, force NTLMv2, disable LLMNR/WPAD?" {
    Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "SMB1" 0 | Out-Null
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "LmCompatibilityLevel" 5 | Out-Null
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "EnableMulticast" 0 | Out-Null
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad" "WpadOverride" 1 | Out-Null
    Write-OK "Legacy protocol hardening applied."
}) {
    $changes += 4
}

Write-Host ""
Write-Step "LSA PROTECTION"
Write-Host ""
$runAsPpl = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "RunAsPPL" $null
Write-Info "RunAsPPL: $(if ($null -eq $runAsPpl) { 'not configured' } else { $runAsPpl })"
if (Invoke-ZeroTrustChange "Enable LSA protection (RunAsPPL)? Requires reboot and can affect legacy credential providers." {
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "RunAsPPL" 1 | Out-Null
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "RunAsPPLBoot" 1 | Out-Null
    Write-OK "LSA protection enabled."
}) {
    $changes += 2
}

Write-Host ""
Write-Step "DEFENDER ASR"
Write-Host ""
$asrRules = @{
    "92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B" = "Block Win32 API calls from Office macros"
    "D4F940AB-401B-4EFC-AADC-AD5F3C50688A" = "Block all Office apps from creating child processes"
    "D4F040A5-4052-402B-9E50-46308FD014A3" = "Block credential stealing from LSASS"
    "D3E037E1-3EB8-44C8-A917-57927947596D" = "Block JavaScript/VBScript from launching downloaded executable"
}
try {
    $mp = Get-MpPreference -ErrorAction Stop
    Write-Info "Existing ASR rule count: $(@($mp.AttackSurfaceReductionRules_Ids).Count)"
    if (Invoke-ZeroTrustChange "Enable selected Defender ASR rules in block mode?" {
        foreach ($rule in $asrRules.Keys) {
            Add-MpPreference -AttackSurfaceReductionRules_Ids $rule -AttackSurfaceReductionRules_Actions Enabled -ErrorAction SilentlyContinue
        }
        Write-OK "Defender ASR rules applied."
    }) {
        $changes++
    }
} catch {
    Write-Warn "Windows Defender preference API unavailable: $($_.Exception.Message)"
}

Write-Host ""
Write-Separator "=" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)ZERO-TRUST AUDIT SELESAI - $changes perubahan diterapkan$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
