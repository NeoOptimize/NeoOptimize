#Requires -RunAsAdministrator
<# MODULE 11 - STORAGE TIERING & NVMe OPTIMIZER #>
param([switch]$Enforce)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "11" "NVMe" "STORAGE & DIRECTSTORAGE AUDIT"

$changes = 0
$canApply = [bool]$Enforce -or [bool]$Global:NeoOptimizeConfirmAll

function Invoke-StorageChange {
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

Write-Step "TRIM STATE"
Write-Host ""
$trimState = fsutil behavior query DisableDeleteNotify 2>&1
Write-Info (($trimState -join " ").Trim())

if (Invoke-StorageChange "Ensure TRIM/DeleteNotify is enabled for SSD volumes?" {
    fsutil behavior set DisableDeleteNotify 0 2>&1 | Out-Null
    Write-OK "TRIM/DeleteNotify enabled."
}) {
    $changes++
}

Write-Host ""
Write-Step "RETRIM MAINTENANCE"
Write-Host ""
if (Invoke-StorageChange "Run online ReTrim on C: now?" {
    Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue | Out-Null
    Write-OK "ReTrim requested for C:."
}) {
    $changes++
}

Write-Host ""
Write-Step "BYPASSIO / DIRECTSTORAGE READINESS"
Write-Host ""
$bypassIoCheck = fsutil bypassIo state c: 2>&1
if ($bypassIoCheck) {
    $bypassIoCheck | ForEach-Object { Write-Info $_ }
} else {
    Write-Warn "fsutil bypassIo state did not return data on this OS/build."
}
Write-Info "DirectStorage is application/driver managed; NeoOptimize only reports readiness."

Write-Host ""
Write-Step "NTFS / PREFETCH POLICY"
Write-Host ""
$prefetch = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnablePrefetcher" $null
$superfetch = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnableSuperfetch" $null
Write-Info "EnablePrefetcher: $(if ($null -eq $prefetch) { 'not configured' } else { $prefetch })"
Write-Info "EnableSuperfetch: $(if ($null -eq $superfetch) { 'not configured' } else { $superfetch })"
Write-Warn "NeoOptimize no longer runs offline dismount checks or disables Prefetch automatically."

if (Invoke-StorageChange "Disable legacy Prefetch/Superfetch registry values? Use only on dedicated NVMe gaming rigs." {
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnablePrefetcher" 0 | Out-Null
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnableSuperfetch" 0 | Out-Null
    Write-OK "Prefetch/Superfetch registry values disabled after explicit approval."
}) {
    $changes += 2
}

Write-Host ""
Write-Separator "=" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)STORAGE AUDIT SELESAI - $changes perubahan diterapkan$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
