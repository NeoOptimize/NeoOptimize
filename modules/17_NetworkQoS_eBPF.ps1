#Requires -RunAsAdministrator
<# MODULE 17 - NETWORK QoS & CONGESTION CONTROL #>
param([switch]$Enforce)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "17" "NET" "NETWORK QoS & TCP TUNING"

$changes = 0
$canApply = [bool]$Enforce -or [bool]$Global:NeoOptimizeConfirmAll

function Invoke-NetworkChange {
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

Write-Step "TCP GLOBAL STATE"
Write-Host ""
$tcpGlobal = netsh int tcp show global 2>&1
if ($tcpGlobal) { $tcpGlobal | ForEach-Object { Write-Info $_ } }

Write-Host ""
Write-Step "TCP SUPPLEMENTAL PROVIDERS"
Write-Host ""
$supp = netsh int tcp show supplemental 2>&1
if ($supp) { $supp | Select-Object -First 40 | ForEach-Object { Write-Info $_ } }
Write-Info "BBR2/eBPF is not assumed. Windows build support is detected from netsh output only."

if (Invoke-NetworkChange "Apply conservative TCP global defaults: autotuning normal, chimney disabled?" {
    netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
    netsh int tcp set global chimney=disabled 2>&1 | Out-Null
    Write-OK "Conservative TCP global defaults applied."
}) {
    $changes += 2
}

Write-Host ""
Write-Step "RSC / ECN POLICY"
Write-Host ""
Write-Warn "RSC and ECN are not changed automatically; both depend on NIC, driver, router, and workload."
if (Invoke-NetworkChange "Enable ECN globally? Use only after router/NIC compatibility is known." {
    netsh int tcp set global ecncapability=enabled 2>&1 | Out-Null
    Write-OK "ECN enabled."
}) {
    $changes++
}

Write-Host ""
Write-Step "DNS OVER HTTPS POLICY"
Write-Host ""
$doh = Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "DoHPolicy" $null
Write-Info "DoHPolicy: $(if ($null -eq $doh) { 'not configured' } else { $doh })"
Write-Warn "Strict DoH is not enabled automatically because it can break DNS when resolvers are not provisioned."
if (Invoke-NetworkChange "Enforce Windows DoH policy after resolver validation?" {
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "DoHPolicy" 2 | Out-Null
    Write-OK "DoH policy set to strict mode."
}) {
    $changes++
}

Write-Host ""
Write-Separator "=" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)NETWORK AUDIT SELESAI - $changes perubahan diterapkan$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
