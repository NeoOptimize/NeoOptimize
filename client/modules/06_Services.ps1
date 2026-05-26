
#Requires -RunAsAdministrator
<# MODULE 06  SERVICES MANAGER #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "06" "" "SERVICES MANAGER"
if (-not (Test-NeoHighRiskConsent -ActionName "Services Manager" -RiskLevel "High" -Reason "Mengubah startup service Windows. Profil gaming/minimal dapat memengaruhi update, print, search, RDP, SMB, dan telemetry.")) {
    Wait-AnyKey
    return
}

Write-Host "  $($Global:WHITE)$($Global:BOLD)Pilih Profil Optimasi:$($Global:RESET)"
Write-Host ""
Write-Host "  $($Global:CYAN)[1]$($Global:RESET)  HOME / DAILY USE     Seimbang untuk penggunaan sehari-hari"
Write-Host "  $($Global:CYAN)[2]$($Global:RESET)  GAMING MODE          FPS maksimal, latensi terendah"
Write-Host "  $($Global:CYAN)[3]$($Global:RESET)  WORKSTATION / DEV    Developer & profesional"
Write-Host "  $($Global:CYAN)[4]$($Global:RESET)  MINIMAL / SECURITY   Attack surface minimal"
Write-Host "  $($Global:CYAN)[5]$($Global:RESET)  RESTORE DEFAULTS     Kembalikan ke default Windows"
Write-Host ""
	$profile = Read-NeoChoice "  Pilihan [1-5]" @("1","2","3","4","5") "1"

#  UNIVERSAL DISABLE (safe for all) 
Write-Host ""
Write-Step "UNIVERSAL  DISABLE SAFE-TO-DISABLE SERVICES"
Write-Host ""

$universal = @(
    @{N="DiagTrack";          D="Connected User Experiences (Telemetry)"},
    @{N="dmwappushservice";   D="WAP Push Message Routing"},
    @{N="RetailDemo";         D="Retail Demo Service"},
    @{N="MapsBroker";         D="Downloaded Maps Manager"},
    @{N="lfsvc";              D="Geolocation Service"},
    @{N="SharedAccess";       D="Internet Connection Sharing"},
    @{N="RemoteRegistry";     D="Remote Registry"},
    @{N="Fax";                D="Fax Service"},
    @{N="XblAuthManager";     D="Xbox Live Auth Manager"},
    @{N="XblGameSave";        D="Xbox Live Game Save"},
    @{N="XboxNetApiSvc";      D="Xbox Live Networking"},
    @{N="XboxGipSvc";         D="Xbox Accessory Management"},
    @{N="WerSvc";             D="Windows Error Reporting"},
    @{N="wercplsupport";      D="WER Control Panel"},
    @{N="PcaSvc";             D="Program Compatibility Assistant"},
    @{N="TrkWks";             D="Distributed Link Tracking Client"},
    @{N="wisvc";              D="Windows Insider Service"},
    @{N="WMPNetworkSvc";      D="Windows Media Player Network Sharing"},
    @{N="icssvc";             D="Windows Mobile Hotspot"},
    @{N="PhoneSvc";           D="Phone Service"},
    @{N="PrintNotify";        D="Printer Extensions & Notifications"},
    @{N="autotimesvc";        D="Cellular Time (if no mobile)"},
    @{N="NcdAutoSetup";       D="Network Connected Devices Auto-Setup"},
    @{N="SEMgrSvc";           D="Payments & NFC/SE Manager"}
)
foreach ($s in $universal) { Set-ServiceState $s.N "Disabled" $true $s.D }

#  Profile-Specific 
Write-Host ""

switch ($profile) {
    "1" { # HOME
        Write-Step "HOME / DAILY USE PROFILE"
        Write-Host ""
        $off = @(
            @{N="SysMain";           D="Superfetch (disable for SSD)"},
            @{N="WSearch";           D="Windows Search Indexing"},
            @{N="Spooler";           D="Print Spooler (no printer)"},
            @{N="TabletInputService";D="Touch Keyboard & Handwriting"}
        )
        $on = @(
            @{N="AudioSrv";          D="Windows Audio"},
            @{N="AudioEndpointBuilder";D="Audio Endpoint"},
            @{N="wuauserv";          D="Windows Update"},
            @{N="Themes";            D="Themes"},
            @{N="W32tm";             D="Windows Time"}
        )
        foreach ($s in $off) { Set-ServiceState $s.N "Disabled" $true $s.D }
        foreach ($s in $on)  { Set-ServiceState $s.N "Automatic" $false $s.D }
        Write-OK "Profile HOME diterapkan"
    }

    "2" { # GAMING
        Write-Step "GAMING MODE PROFILE"
        Write-Host ""
        $off = @(
            @{N="SysMain";           D="Superfetch"},
            @{N="WSearch";           D="Windows Search"},
            @{N="Spooler";           D="Print Spooler"},
            @{N="wuauserv";          D="Windows Update (gunakan manual)"},
            @{N="BITS";              D="Background Transfer"},
            @{N="TabletInputService";D="Touch Keyboard"},
            @{N="WbioSrvc";          D="Biometric"},
            @{N="defragsvc";         D="Disk Defrag"},
            @{N="DPS";               D="Diagnostic Policy"},
            @{N="WdiServiceHost";    D="Diagnostic Service Host"},
            @{N="WdiSystemHost";     D="Diagnostic System Host"},
            @{N="DusmSvc";           D="Data Usage"}
        )
        $mustOn = @(
            @{N="AudioSrv";          D="Windows Audio"},
            @{N="AudioEndpointBuilder";D="Audio Endpoint"},
            @{N="nsi";               D="Network Store Interface"},
            @{N="Dhcp";              D="DHCP Client"},
            @{N="Dnscache";          D="DNS Client"},
            @{N="BFE";               D="Base Filtering Engine"},
            @{N="mpssvc";            D="Windows Firewall"}
        )
        foreach ($s in $off)    { Set-ServiceState $s.N "Disabled" $true $s.D }
        foreach ($s in $mustOn) { Set-ServiceState $s.N "Automatic" $false $s.D }

        # GPU + MMCSS Priority
        $gamesPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        if (-not (Test-Path $gamesPath)) { New-Item -Path $gamesPath -Force | Out-Null }
	        Set-Reg $gamesPath "GPU Priority"          8     "DWord" | Out-Null
	        Set-Reg $gamesPath "Priority"              6     "DWord" | Out-Null
	        Set-Reg $gamesPath "Scheduling Category"   "High" "String" | Out-Null
	        Set-Reg $gamesPath "SFIO Priority"         "High" "String" | Out-Null
	        Set-Reg $gamesPath "Clock Rate"            10000 "DWord" | Out-Null
	        Set-Reg $gamesPath "Affinity"              0     "DWord" | Out-Null
        Write-OK "GPU Priority=8, Scheduling=High, SFIO=High"
        Write-OK "Profile GAMING diterapkan"
    }

    "3" { # WORKSTATION
        Write-Step "WORKSTATION / DEVELOPER PROFILE"
        Write-Host ""
        $off = @(
            @{N="SysMain";           D="Superfetch"},
            @{N="TabletInputService";D="Touch Keyboard"},
            @{N="Spooler";           D="Print Spooler (no printer)"}
        )
        $manual = @(
            @{N="WSearch";           D="Windows Search"},
            @{N="wuauserv";          D="Windows Update (manual)"},
            @{N="defragsvc";         D="Disk Defrag (manual)"}
        )
        $on = @(
            @{N="AudioSrv";          D="Audio"},
            @{N="Dnscache";          D="DNS Cache"},
            @{N="W32tm";             D="Windows Time"},
            @{N="LanmanWorkstation"; D="Workstation (network)"},
            @{N="LanmanServer";      D="Server (file share)"},
            @{N="wuauserv";          D="Windows Update"}
        )
        foreach ($s in $off)    { Set-ServiceState $s.N "Disabled" $true $s.D }
        foreach ($s in $manual) { Set-ServiceState $s.N "Manual" $false $s.D }
        foreach ($s in $on)     { Set-ServiceState $s.N "Automatic" $false $s.D }
        Write-OK "Profile WORKSTATION diterapkan"
    }

    "4" { # MINIMAL
        Write-Step "MINIMAL / SECURITY PROFILE"
        Write-Host ""
        $aggressive = @(
            @{N="SysMain";           D="Superfetch"},
            @{N="WSearch";           D="Windows Search"},
            @{N="Spooler";           D="Print Spooler"},
            @{N="wuauserv";          D="Windows Update"},
            @{N="BITS";              D="Background Transfer"},
            @{N="RemoteAccess";      D="Routing & Remote Access"},
            @{N="SessionEnv";        D="Remote Desktop Config"},
            @{N="TermService";       D="Remote Desktop Services"},
            @{N="UmRdpService";      D="RDP Device Redirector"},
            @{N="LanmanServer";      D="Server (SMB)"},
            @{N="Browser";           D="Computer Browser"},
            @{N="SSDPSRV";           D="SSDP Discovery"},
            @{N="upnphost";          D="UPnP Device Host"},
            @{N="ALG";               D="Application Layer Gateway"},
            @{N="FDResPub";          D="Function Discovery Resource Publication"},
            @{N="fdPHost";           D="Function Discovery Provider Host"}
        )
        foreach ($s in $aggressive) { Set-ServiceState $s.N "Disabled" $true $s.D }
        Write-OK "Profile MINIMAL/SECURITY diterapkan"
    }

	    "5" { # RESTORE
	        Write-Step "RESTORE DEFAULTS"
	        Write-Host ""
	        if (-not (Restore-ServiceStartupBackup)) {
	            $restore = @(
	                "SysMain","WSearch","Spooler","wuauserv","BITS","AudioSrv",
	                "Themes","W32tm","Dnscache","LanmanWorkstation","LanmanServer",
	                "AudioEndpointBuilder","BFE","mpssvc","Dhcp","nsi"
	            )
	            foreach ($n in $restore) { Set-ServiceState $n "Automatic" $false $n }
	            Write-OK "Default services fallback diterapkan"
	        }
	    }
	}

#  Critical Services Status Check 
Write-Host ""
Write-Step "STATUS LAYANAN KRITIS"
Write-Host ""
Write-Host "  $($Global:DIM)$("SERVICE".PadRight(30)) $("STATUS".PadRight(12)) STARTUP$($Global:RESET)"
$critical = @("AudioSrv","Dnscache","BFE","mpssvc","EventLog","PlugPlay","RpcSs","LSM","WinDefend")
foreach ($n in $critical) {
    $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
    if ($svc) {
        $color   = if ($svc.Status -eq "Running") { $Global:GREEN } else { $Global:RED }
        $startup = (Get-WmiObject Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue).StartMode
        Write-Host "  $($svc.DisplayName.PadRight(30)) ${color}$($svc.Status.ToString().PadRight(12))$($Global:RESET) $startup"
    }
}

Write-Host ""
Write-Separator "" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)   SERVICES MANAGER SELESAI$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
