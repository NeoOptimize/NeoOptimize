
#Requires -RunAsAdministrator
<# MODULE 04 — NETWORK OPTIMIZER #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "04" "🌐" "NETWORK OPTIMIZER"

# ── 1. TCP/IP Stack ────────────────────────────────────────────────────────────
Write-Step "TCP/IP STACK TWEAKS"
Write-Host ""
$tcpParams = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
$tcpTweaks = @(
    @("TcpMaxDataRetransmissions",5), @("TcpTimedWaitDelay",30),
    @("DefaultTTL",64),               @("Tcp1323Opts",3),
    @("TcpMaxSackRetransmits",3),      @("SackOpts",1),
    @("TCPInitialRTT",300),            @("EnableICMPRedirect",0),
    @("EnablePMTUDiscovery",1),        @("NoNameReleaseOnDemand",1),
    @("KeepAliveTime",300000),         @("KeepAliveInterval",1000)
)
foreach ($t in $tcpTweaks) { Set-Reg $tcpParams $t[0] $t[1] | Out-Null }
Write-OK "TCP/IP: TTL=64, SACK=on, RFC1323=on, KeepAlive tuned"

# ── 2. TCP Global (netsh) ──────────────────────────────────────────────────────
Write-Host ""
Write-Step "TCP GLOBAL SETTINGS"
Write-Host ""
$netshCmds = @(
    "int tcp set global autotuninglevel=normal",
    "int tcp set global chimney=disabled",
    "int tcp set global dca=enabled",
    "int tcp set global ecncapability=disabled",
    "int tcp set global timestamps=disabled",
    "int tcp set global rss=enabled",
    "int tcp set global fastopen=enabled",
    "int tcp set global fastopenfallback=enabled",
    "int tcp set global hystart=disabled",
    "int tcp set global pacingprofile=off"
)
foreach ($cmd in $netshCmds) {
    netsh $cmd 2>&1 | Out-Null
}
Write-OK "TCP: AutoTuning, RSS, FastOpen, DCA applied"

# ── 3. Nagle's Algorithm ───────────────────────────────────────────────────────
Write-Host ""
Write-Step "NAGLE'S ALGORITHM (DISABLE — Lower Latency)"
Write-Host ""
$ifPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
$ifCount = 0
Get-ChildItem -Path $ifPath -ErrorAction SilentlyContinue | ForEach-Object {
    Set-Reg $_.PSPath "TcpAckFrequency" 1 | Out-Null
    Set-Reg $_.PSPath "TcpNoDelay"      1 | Out-Null
    Set-Reg $_.PSPath "TCPDelAckTicks"  0 | Out-Null
    $ifCount++
}
Write-OK "Nagle's Algorithm disabled on $ifCount network interfaces"

# ── 4. DNS Configuration ───────────────────────────────────────────────────────
Write-Host ""
Write-Step "DNS SERVER CONFIGURATION"
Write-Host ""
Write-Host "  $($Global:WHITE)Pilih DNS Provider:$($Global:RESET)"
Write-Host ""
Write-Host "  $($Global:CYAN)[1]$($Global:RESET) ⚡ Cloudflare  $($Global:DIM)1.1.1.1 / 1.0.0.1$($Global:RESET)         — Tercepat"
Write-Host "  $($Global:CYAN)[2]$($Global:RESET) 🔵 Google      $($Global:DIM)8.8.8.8 / 8.8.4.4$($Global:RESET)         — Paling andal"
Write-Host "  $($Global:CYAN)[3]$($Global:RESET) 🔒 Quad9       $($Global:DIM)9.9.9.9 / 149.112.112.112$($Global:RESET) — Aman (block malware)"
Write-Host "  $($Global:CYAN)[4]$($Global:RESET) 🇮🇩 Cloudflare ID  $($Global:DIM)1.1.1.3 / 1.0.0.3$($Global:RESET)    — Family filter"
Write-Host "  $($Global:CYAN)[5]$($Global:RESET) ─  Lewati"
Write-Host ""
	$dns = Read-NeoChoice "  Pilihan [1-5]" @("1","2","3","4","5") "5"

$pri = $sec = $null; $dnsName = ""
switch ($dns) {
    "1" { $pri="1.1.1.1";     $sec="1.0.0.1";          $dnsName="Cloudflare" }
    "2" { $pri="8.8.8.8";     $sec="8.8.4.4";           $dnsName="Google" }
    "3" { $pri="9.9.9.9";     $sec="149.112.112.112";   $dnsName="Quad9" }
    "4" { $pri="1.1.1.3";     $sec="1.0.0.3";           $dnsName="Cloudflare Family" }
    "5" { Write-Skip "DNS config" }
}
if ($pri) {
    Get-NetAdapter -Physical | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        Set-DnsClientServerAddress -InterfaceAlias $_.Name -ServerAddresses ($pri,$sec) -ErrorAction SilentlyContinue
        Write-OK "DNS $dnsName set on: $($_.Name)"
    }
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "EnableAutoDoh" 2
    Write-OK "DNS-over-HTTPS (DoH): ENABLED"
    # Flush DNS after change
    ipconfig /flushdns 2>&1 | Out-Null
    Write-OK "DNS cache flushed"
}

# ── 5. QoS Bandwidth Reserve Removal ──────────────────────────────────────────
Write-Host ""
Write-Step "QoS BANDWIDTH THROTTLE REMOVAL"
Write-Host ""
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched" "NonBestEffortLimit" 0
Write-OK "QoS reserve removed — 100% bandwidth available"

# ── 6. Network Throttling ──────────────────────────────────────────────────────
Write-Host ""
Write-Step "NETWORK THROTTLING"
Write-Host ""
$mmPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
Set-Reg $mmPath "NetworkThrottlingIndex" 0xffffffff
Set-Reg $mmPath "SystemResponsiveness"   0
Write-OK "Network throttling: DISABLED"

# ── 7. IPv6 Tunneling ──────────────────────────────────────────────────────────
Write-Host ""
Write-Step "IPv6 TUNNELING (Teredo/6to4/ISATAP)"
Write-Host ""
netsh interface teredo set state disabled   2>&1 | Out-Null
netsh interface 6to4   set state disabled   2>&1 | Out-Null
netsh interface isatap set state disabled   2>&1 | Out-Null
	Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" "DisabledComponents" 0x01
	Write-OK "IPv6 tunnel interfaces: DISABLED; native IPv6 tetap aktif"

# ── 8. NetBIOS Disable ─────────────────────────────────────────────────────────
Write-Host ""
Write-Step "NetBIOS OVER TCP/IP"
Write-Host ""
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces" -ErrorAction SilentlyContinue | ForEach-Object {
    Set-ItemProperty -Path $_.PSPath -Name "NetbiosOptions" -Value 2 -ErrorAction SilentlyContinue
}
Write-OK "NetBIOS over TCP/IP: DISABLED on all adapters"

# ── 9. Winsock Reset ───────────────────────────────────────────────────────────
Write-Host ""
Write-Step "WINSOCK CATALOG RESET"
Write-Host ""
netsh winsock reset catalog 2>&1 | Out-Null
Write-OK "Winsock catalog: RESET (restart diperlukan)"

# ── 10. Network Adapter Optimization ──────────────────────────────────────────
Write-Host ""
Write-Step "NETWORK ADAPTER OPTIMIZATION"
Write-Host ""
Get-NetAdapter -Physical | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
    $n = $_.Name
    Set-NetAdapterRss -Name $n -Enabled $true -ErrorAction SilentlyContinue
    Disable-NetAdapterPowerManagement -Name $n -WakeOnMagicPacket -WakeOnPattern -ErrorAction SilentlyContinue
    Write-OK "Adapter: $n — RSS enabled, power saving off"
}

# ── 11. Hosts File — Ad/Tracker Block ──────────────────────────────────────────
Write-Host ""
Write-Step "HOSTS FILE — AD/TRACKER BLOCK"
Write-Host ""
	$adDomains = @(
	    "ads.google.com",
	    "googleads.g.doubleclick.net",
	    "pagead2.googlesyndication.com",
	    "www.google-analytics.com",
	    "ssl.google-analytics.com",
	    "analytics.google.com",
	    "stats.g.doubleclick.net",
	    "adservice.google.com",
	    "pubads.g.doubleclick.net",
	    "tpc.googlesyndication.com",
	    "scorecardresearch.com",
	    "beacon.scorecardresearch.com",
	    "pixel.quantserve.com",
	    "api.segment.io",
	    "cdn.segment.com",
	    "cdn.mxpnl.com",
	    "tracking.g.doubleclick.net",
	    "ad.doubleclick.net",
	    "cm.g.doubleclick.net",
	    "static.doubleclick.net"
	)
	Add-HostsBlock "AdsTrackers" $adDomains | Out-Null

# ── 12. Adapter Summary ────────────────────────────────────────────────────────
Write-Host ""
Write-Step "NETWORK ADAPTER SUMMARY"
Write-Host ""
Write-Host "  $($Global:DIM)$("ADAPTER".PadRight(30)) $("SPEED".PadRight(20)) STATUS$($Global:RESET)"
Get-NetAdapter | ForEach-Object {
    $color  = if ($_.Status -eq "Up") { $Global:GREEN } else { $Global:DIM }
    $speed  = if ($_.LinkSpeed) { $_.LinkSpeed } else { "N/A" }
    Write-Host "  ${color}$($_.Name.PadRight(30)) $($speed.ToString().PadRight(20)) $($_.Status)$($Global:RESET)"
}

Write-Host ""
Write-Separator "═" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)  ✅ NETWORK OPTIMIZER SELESAI$($Global:RESET)"
Write-Host ""
Write-Host "  $($Global:YELLOW)⚠  Restart untuk menerapkan reset Winsock & TCP stack.$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
