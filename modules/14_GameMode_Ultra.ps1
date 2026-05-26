#Requires -RunAsAdministrator
<# MODULE 14 - GAME MODE ULTRA #>
param([switch]$Enforce)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "14" "GAME" "GAME MODE ULTRA"

$changes = 0
$canApply = [bool]$Enforce -or [bool]$Global:NeoOptimizeConfirmAll

function Invoke-GameChange {
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

Write-Step "CPU POWER PROFILE"
Write-Host ""
$schemeOutput = powercfg /getactivescheme 2>&1
Write-Info (($schemeOutput -join " ").Trim())
if (($schemeOutput -join " ") -match "GUID:\s+([-a-fA-F0-9]+)") {
    $activeScheme = $Matches[1]
    if (Invoke-GameChange "Set processor core parking minimum cores to 100% on AC power?" {
        powercfg -setacvalueindex $activeScheme SUB_PROCESSOR 0cc5b647-c1df-4637-891a-dec35c318583 100 2>&1 | Out-Null
        powercfg -setactive $activeScheme 2>&1 | Out-Null
        Write-OK "Core parking minimum cores set to 100% for active power scheme."
    }) {
        $changes++
    }
} else {
    Write-Warn "Active power scheme GUID tidak terdeteksi."
}

Write-Host ""
Write-Step "GPU SCHEDULING"
Write-Host ""
$hags = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" $null
Write-Info "HwSchMode: $(if ($null -eq $hags) { 'Windows default' } else { $hags })"
if (Invoke-GameChange "Enable Hardware-Accelerated GPU Scheduling policy override?" {
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2 | Out-Null
    Write-OK "HAGS policy override enabled."
}) {
    $changes++
}

Write-Host ""
Write-Step "MMCSS GAME PROFILE"
Write-Host ""
$profilePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
$gamePath = "$profilePath\Tasks\Games"
Write-Info "SystemResponsiveness: $(Get-RegValue $profilePath 'SystemResponsiveness' 'not configured')"
Write-Info "NetworkThrottlingIndex: $(Get-RegValue $profilePath 'NetworkThrottlingIndex' 'not configured')"
Write-Info "Games GPU Priority: $(Get-RegValue $gamePath 'GPU Priority' 'not configured')"

if (Invoke-GameChange "Apply MMCSS gaming profile registry values?" {
    Set-Reg $profilePath "SystemResponsiveness" 0 | Out-Null
    Set-Reg $profilePath "NetworkThrottlingIndex" 4294967295 "DWord" | Out-Null
    Set-Reg $gamePath "GPU Priority" 8 | Out-Null
    Set-Reg $gamePath "Priority" 6 | Out-Null
    Write-OK "MMCSS game profile applied."
}) {
    $changes += 4
}

Write-Host ""
Write-Step "BOOT TIMER POLICY"
Write-Host ""
Write-Warn "BCDEdit timer changes are not applied by this release module."
Write-Info "Reason: platform clock/dynamic tick tuning is hardware-dependent and hard to validate safely."

Write-Host ""
Write-Separator "=" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)GAME MODE AUDIT SELESAI - $changes perubahan diterapkan$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
