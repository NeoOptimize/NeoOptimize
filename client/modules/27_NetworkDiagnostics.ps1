#Requires -RunAsAdministrator
<# MODULE 27 - NETWORK DIAGNOSTICS #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "27" "NET" "NETWORK DIAGNOSTICS"

$targets = @(
    [PSCustomObject]@{ Name="Microsoft"; Host="www.microsoft.com"; Port=443 },
    [PSCustomObject]@{ Name="Windows NCSI"; Host="dns.msftncsi.com"; Port=80 },
    [PSCustomObject]@{ Name="Cloudflare DNS"; Host="1.1.1.1"; Port=53 }
)

Write-Step "ADAPTERS"
Write-Host ""
$adapters = @(Get-NetAdapter | Sort-Object Name | Select-Object Name, Status, LinkSpeed, InterfaceDescription, MacAddress)
foreach ($adapter in $adapters) {
    Write-Host ("  {0,-28} {1,-10} {2}" -f $adapter.Name, $adapter.Status, $adapter.LinkSpeed)
}

Write-Host ""
Write-Step "IP / DNS CONFIGURATION"
Write-Host ""
$ipConfig = @(Get-NetIPConfiguration | Select-Object InterfaceAlias, IPv4Address, IPv6Address, IPv4DefaultGateway, DNSServer)
foreach ($cfg in $ipConfig) {
    $ipv4 = ($cfg.IPv4Address | Select-Object -First 1).IPAddress
    $gateway = ($cfg.IPv4DefaultGateway | Select-Object -First 1).NextHop
    $dns = ($cfg.DNSServer.ServerAddresses -join ",")
    Write-Host ("  {0,-28} IPv4={1,-16} GW={2} DNS={3}" -f $cfg.InterfaceAlias, $ipv4, $gateway, $dns)
}

Write-Host ""
Write-Step "CONNECTIVITY TESTS"
Write-Host ""
$tests = New-Object System.Collections.Generic.List[object]
foreach ($target in $targets) {
    $result = Test-NetConnection -ComputerName $target.Host -Port $target.Port -InformationLevel Detailed
    $row = [PSCustomObject]@{
        name = $target.Name
        host = $target.Host
        port = $target.Port
        resolved = $result.RemoteAddress
        ping = $result.PingSucceeded
        tcp = $result.TcpTestSucceeded
        interface = $result.InterfaceAlias
        source = $result.SourceAddress
    }
    $tests.Add($row) | Out-Null
    $state = if ($row.tcp -or ($target.Port -eq 53 -and $row.ping)) { "OK" } else { "WARN" }
    Write-Info ("{0}: host={1} port={2} ping={3} tcp={4} [{5}]" -f $target.Name, $target.Host, $target.Port, $row.ping, $row.tcp, $state)
}

$report = [PSCustomObject]@{
    captured_at = (Get-Date).ToString("o")
    adapters = $adapters
    ip_configuration = $ipConfig
    routes = @(Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object InterfaceAlias, NextHop, RouteMetric, ifMetric)
    dns_client = @(Get-DnsClientServerAddress | Select-Object InterfaceAlias, AddressFamily, ServerAddresses)
    tcp_settings = @(Get-NetTCPSetting | Select-Object SettingName, CongestionProvider, AutoTuningLevelLocal, ScalingHeuristics)
    tests = $tests
}

$dir = Join-Path $Global:LogDir "network"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$path = Join-Path $dir ("network-diagnostics_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
Write-OK "Network diagnostics report: $path"
Write-Footer
Wait-AnyKey
