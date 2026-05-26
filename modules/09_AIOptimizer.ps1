#Requires -RunAsAdministrator
<# MODULE 09 - AI & NPU OPTIMIZER #>
param([switch]$Enforce)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "09" "AI" "AI & NPU OPTIMIZER"

$changes = 0
$canApply = [bool]$Enforce -or [bool]$Global:NeoOptimizeConfirmAll

function Invoke-HighRiskAiChange {
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

Write-Step "AI/NPU DEVICE INVENTORY"
Write-Host ""
$aiDevices = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "NPU|Neural|AI Boost|Ryzen AI|VPU|Movidius|Hexagon" } |
    Select-Object -First 10

if ($aiDevices) {
    foreach ($device in $aiDevices) {
        Write-Info ("{0} [{1}]" -f $device.Name, $device.Status)
    }
} else {
    Write-Info "Tidak ada NPU/VPU yang terdeteksi melalui PnP inventory."
}

Write-Host ""
Write-Step "WINDOWS AI / COPILOT POLICY"
Write-Host ""
$copilotPolicy = Get-RegValue "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" $null
if ($null -eq $copilotPolicy) {
    Write-Info "Windows Copilot policy: not configured"
} elseif ([int]$copilotPolicy -eq 1) {
    Write-OK "Windows Copilot policy: disabled by policy"
} else {
    Write-Info "Windows Copilot policy: enabled/not blocked"
}

if (Invoke-HighRiskAiChange "Disable Windows Copilot for current user via supported policy?" {
    Set-Reg "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1 | Out-Null
    Write-OK "Windows Copilot disabled for current user policy."
}) {
    $changes++
}

Write-Host ""
Write-Step "ML CACHE / MEMORY POLICY"
Write-Host ""
$largeSystemCache = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "LargeSystemCache" 0
$ioPageLockLimit = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "IoPageLockLimit" $null
Write-Info "LargeSystemCache current value: $largeSystemCache"
Write-Info "IoPageLockLimit current value: $(if ($null -eq $ioPageLockLimit) { 'not configured' } else { $ioPageLockLimit })"
Write-Warn "Kernel memory cache tuning is not applied automatically; wrong values can reduce stability on mixed workloads."

if (Invoke-HighRiskAiChange "Apply conservative server-style ML cache hint? Recommended only for dedicated local inference hosts." {
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "IoPageLockLimit" 67108864 | Out-Null
    Write-OK "IoPageLockLimit set to 64MB. Existing registry key was backed up first."
}) {
    $changes++
}

Write-Host ""
Write-Separator "=" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)AI & NPU AUDIT SELESAI - $changes perubahan diterapkan$($Global:RESET)"
Write-Host ""
Write-Host "  $($Global:YELLOW)Gunakan -Enforce atau konfirmasi manual untuk perubahan policy/cache.$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
