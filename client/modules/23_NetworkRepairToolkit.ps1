#Requires -RunAsAdministrator
<# MODULE 23 - NETWORK REPAIR TOOLKIT #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "23" "NET" "NETWORK REPAIR TOOLKIT"

Write-Step "ADAPTER STATUS"
Write-Host ""
Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,-28} {1,-10} {2}" -f $_.Name, $_.Status, $_.InterfaceDescription)
}

Write-Host ""
Write-Step "IP CONFIGURATION SNAPSHOT"
Write-Host ""
Get-NetIPConfiguration -ErrorAction SilentlyContinue | ForEach-Object {
    $ipv4 = ($_.IPv4Address | Select-Object -First 1).IPAddress
    $gw = ($_.IPv4DefaultGateway | Select-Object -First 1).NextHop
    Write-Host ("  {0,-28} IPv4={1,-16} GW={2}" -f $_.InterfaceAlias, $ipv4, $gw)
}

if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) {
    Write-Warn "Non-interactive mode: audit only."
    Wait-AnyKey
    return
}

Write-Host ""
Write-Host "  [1] Flush DNS cache"
Write-Host "  [2] Renew DHCP leases"
Write-Host "  [3] Reset WinHTTP proxy"
Write-Host "  [4] Reset Winsock and TCP/IP stack (restart required)"
Write-Host "  [5] Run all safe repairs (1-3)"
Write-Host ""
$choice = Read-NeoChoice "  Pilihan [1-5]" @("1","2","3","4","5") "1"

if ($choice -in @("1","5")) {
    ipconfig /flushdns | Out-Null
    Write-OK "DNS cache flushed."
}
if ($choice -in @("2","5")) {
    ipconfig /release | Out-Null
    ipconfig /renew | Out-Null
    Write-OK "DHCP release/renew requested."
}
if ($choice -in @("3","5")) {
    netsh winhttp reset proxy | Out-Null
    Write-OK "WinHTTP proxy reset."
}
if ($choice -eq "4") {
    if (Confirm-NeoAction "Reset Winsock and TCP/IP stack? Restart is required." $false) {
        netsh winsock reset | Out-Null
        netsh int ip reset | Out-Null
        Write-OK "Winsock/TCP-IP reset requested. Restart Windows."
    }
}

Write-Host ""
Write-Separator "=" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)NETWORK REPAIR TOOLKIT SELESAI$($Global:RESET)"
Write-Footer
Wait-AnyKey
