
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    NeoOptimize v1.0  Windows Optimizer & Agent
    Professional Tool for Computer Technicians

.DESCRIPTION
    One-Stop Solution untuk optimasi Windows 10/11.
    Dilengkapi 8 modul optimasi profesional.

.NOTES
    Author  : NeoOptimize Team
    Version : 1.0
    Requires: PowerShell 5.1+, Windows 10/11, Run as Administrator
#>

param(
    [ValidateSet("Dashboard", "Permissions", "Cleaner", "Performance", "Privacy", "Network", "Security", "DefenderAuditMode", "Collect", "Services", "Updates", "Power", "Apps", "StartupOptimizer", "ComponentCleanup", "EventLogMaintenance", "FeatureOptimizer", "NetworkRepair", "DeviceSnapshot", "BenchmarkReport", "PrivacyReview", "NetworkDiagnostics", "ContainerHyperVTuning", "ZeroTrustSecurity", "GameModeUltra", "AINPUCaching", "StorageTiering", "RemoteReadiness", "UpdateRepair", "PowerPlanTuning", "SecurityAudit", "Maintenance", "CleanAll", "ScheduleClean", "SmartBooster", "SmartOptimize", "Profile", "Backup", "ThreatMonitor", "Autoimmune", "IntegrityScan", "DeepScan", "SystemDiagnostics", "SystemRepair", "WindowsDoctor", "WindowsErrorFix", "DiskStatus", "DiskScan", "DiskRepair", "DiskOptimize", "HealthRepair", "RestorePoint", "RollbackLast", "FreeAgent", "FreeAgentProviders", "NullClawDocs", "AIPlan", "AIInteractive", "NEOAgentic", "AIScriptForge", "AICatalog", "AIProviders", "AIEnvironment", "AITrain", "LocalAISetup", "VoiceCommand", "CloudStatus", "CloudOpen", "AgentAudit", "AgentRemediate", "AgentInstall", "AgentStatus", "AgentUninstall", "RemoteAccess", "NeoUpdate")]
    [string]$Action = "",
    [switch]$FullAuto,
    [switch]$NoPause,
    [switch]$AssumeYes,
    [switch]$ConfirmAll,
    [switch]$Enforce
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference    = "SilentlyContinue"

#  Load Common Library 
$LibPath = "$PSScriptRoot\lib\Common.ps1"
if (-not (Test-Path $LibPath)) {
    Write-Host "ERROR: lib\Common.ps1 not found. Pastikan semua file NeoOptimize ada di folder yang sama." -ForegroundColor Red
    pause; exit 1
}
. $LibPath

# Intercept Help raw arguments
if ($args -contains "/help" -or $args -contains "-help" -or $args -contains "-h" -or $args -contains "/h" -or $args -contains "-?") {
    Show-HelpGuide
    Wait-AnyKey
    exit 0
}

$Global:NeoOptimizeSkipPause = [bool]$NoPause
$Global:NeoOptimizeAssumeYes = [bool]$AssumeYes
$Global:NeoOptimizeConfirmAll = [bool]$ConfirmAll
$Global:NeoOptimizeEnforce = [bool]$Enforce
if ($FullAuto) {
    $Global:NeoOptimizeNonInteractive = $true
    $Global:NeoOptimizeSkipPause = $true
}

#  Admin Check 
if (-not (Test-IsAdmin)) {
    Write-Host ""
    Write-Host "  ERROR: Jalankan sebagai Administrator!" -ForegroundColor Red
    Write-Host "  Klik kanan NeoOptimize.ps1  'Run as Administrator'" -ForegroundColor Yellow
    Start-Sleep 3
    exit 1
}


#  Module Runner 
function Invoke-Module {
    param($FileName)
    $path = "$PSScriptRoot\modules\$FileName"
    if (Test-Path $path) {
        $actionName = Resolve-NeoModuleAction $FileName
        if ($actionName) {
            $modulePath = $path
            Invoke-NeoActionWithSafety -ActionName $actionName -ScriptBlock { . $modulePath }
            return
        }
        . $path
    } else {
        Write-Host ""
        Write-Err "Modul tidak ditemukan: $FileName"
        Write-Info "Pastikan folder modules\ lengkap."
        Wait-AnyKey
    }
}

function Invoke-AgentConsole {
    $agentPath = Join-Path $PSScriptRoot "NeoOptimizeAgent.ps1"
    if (-not (Test-Path $agentPath)) {
        Write-Err "NeoOptimizeAgent.ps1 tidak ditemukan."
        Wait-AnyKey
        return
    }

    Write-NeoLogo -Compact
    Write-SectionHeader "" "NEOOPTIMIZE AGENT" "Audit, score, report, scheduled task"
    Write-Host "  $($Global:CYAN)[1]$($Global:RESET) Audit & Score sekarang"
    Write-Host "  $($Global:CYAN)[2]$($Global:RESET) Remediate aman berdasarkan audit"
    Write-Host "  $($Global:CYAN)[3]$($Global:RESET) Install scheduled daily agent"
    Write-Host "  $($Global:CYAN)[4]$($Global:RESET) Status agent"
    Write-Host "  $($Global:CYAN)[5]$($Global:RESET) Uninstall scheduled agent"
    Write-Host "  $($Global:CYAN)[0]$($Global:RESET) Kembali"
    Write-Host ""
    $agentChoice = Read-NeoChoice "  Pilihan [0-5]" @("0","1","2","3","4","5") "1"

    switch ($agentChoice) {
        "1" { & $agentPath -Mode Audit }
        "2" { & $agentPath -Mode Remediate }
        "3" { & $agentPath -Mode Install }
        "4" { & $agentPath -Mode Status }
        "5" { & $agentPath -Mode Uninstall }
        default { return }
    }
    Wait-AnyKey
}

function Invoke-MaintenanceModule {
    param([string]$Mode = "Menu")
    $maintenancePath = Join-Path $PSScriptRoot "modules\09_Maintenance.ps1"
    if (-not (Test-Path $maintenancePath)) {
        Write-Err "Modul maintenance tidak ditemukan."
        Wait-AnyKey
        return
    }
    $actionName = Resolve-NeoMaintenanceAction $Mode
    if ($actionName) {
        Invoke-NeoActionWithSafety -ActionName $actionName -ScriptBlock { & $maintenancePath -Mode $Mode }
        return
    }
    & $maintenancePath -Mode $Mode
}

function Resolve-NeoModuleAction {
    param([string]$FileName)
    $map = @{
        "00_Permissions.ps1" = "Permissions"
        "01_Cleaner.ps1" = "Cleaner"
        "02_Performance.ps1" = "Performance"
        "03_Privacy.ps1" = "Privacy"
        "04_Network.ps1" = "Network"
        "05_Security.ps1" = "Security"
        "06_Collect.ps1" = "Collect"
        "06_Services.ps1" = "Services"
        "07_Updates.ps1" = "Updates"
        "08_Power.ps1" = "Power"
        "09_Apps.ps1" = "Apps"
        "19_StartupOptimizer.ps1" = "StartupOptimizer"
        "20_ComponentCleanup.ps1" = "ComponentCleanup"
        "21_EventLogMaintenance.ps1" = "EventLogMaintenance"
        "22_WindowsFeatureOptimizer.ps1" = "FeatureOptimizer"
        "23_NetworkRepairToolkit.ps1" = "NetworkRepair"
        "24_DeviceSnapshot.ps1" = "DeviceSnapshot"
        "25_BenchmarkReport.ps1" = "BenchmarkReport"
        "26_PrivacyReview.ps1" = "PrivacyReview"
        "27_NetworkDiagnostics.ps1" = "NetworkDiagnostics"
        "28_ContainerHyperVTuning.ps1" = "ContainerHyperVTuning"
        "29_ZeroTrustSecurity.ps1" = "ZeroTrustSecurity"
        "30_GameModeUltra.ps1" = "GameModeUltra"
        "31_AINPUCaching.ps1" = "AINPUCaching"
        "32_StorageTiering.ps1" = "StorageTiering"
        "33_RemoteAccessReadiness.ps1" = "RemoteReadiness"
        "34_UpdateRepair.ps1" = "UpdateRepair"
        "35_PowerPlanTuning.ps1" = "PowerPlanTuning"
        "36_SecurityAudit.ps1" = "SecurityAudit"
        "10_Profile.ps1" = "Profile"
        "10_SystemRepair.ps1" = "SystemRepair"
        "11_Backup.ps1" = "Backup"
        "12_ThreatMonitor.ps1" = "ThreatMonitor"
        "13_Autoimmune.ps1" = "Autoimmune"
        "14_IntegrityScan.ps1" = "IntegrityScan"
        "15_DeepScan.ps1" = "DeepScan"
        "16_SystemDiagnostics.ps1" = "SystemDiagnostics"
        "17_NeoOptimizeUpdate.ps1" = "NeoUpdate"
        "18_NeoWindowsDoctor.ps1" = "WindowsDoctor"
    }
    if ($map.ContainsKey($FileName)) { return [string]$map[$FileName] }
    return ""
}

function Resolve-NeoMaintenanceAction {
    param([string]$Mode)
    $map = @{
        "CleanAll" = "CleanAll"
        "SmartBooster" = "SmartBooster"
        "SmartOptimize" = "SmartOptimize"
        "DiskRepair" = "DiskRepair"
        "DiskOptimize" = "DiskOptimize"
        "HealthRepair" = "HealthRepair"
    }
    if ($map.ContainsKey($Mode)) { return [string]$map[$Mode] }
    return ""
}

function Get-NeoActionSafetyProfile {
    param([string]$ActionName)

    $profiles = @{
        Cleaner = @{
            Risk = "Low"
            RegistryKeys = @()
            Services = @()
        }
        Permissions = @{
            Risk = "Medium"
            RegistryKeys = @("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System")
            Services = @("NeoOptimize RMM Agent")
        }
        Collect = @{
            Risk = "Low"
            RegistryKeys = @()
            Services = @()
        }
        CleanAll = @{
            Risk = "Medium"
            RegistryKeys = @("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer", "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer")
            Services = @("wuauserv", "bits")
        }
        Performance = @{
            Risk = "High"
            RegistryKeys = @(
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects",
                "HKCU\Control Panel\Desktop",
                "HKCU\Control Panel\Desktop\WindowMetrics",
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced",
                "HKCU\Software\Microsoft\Windows\DWM",
                "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management",
                "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl",
                "HKCU\System\GameConfigStore",
                "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
            )
            Services = @("SysMain")
        }
        Privacy = @{
            Risk = "High"
            RegistryKeys = @(
                "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection",
                "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo",
                "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy",
                "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager",
                "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search",
                "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager"
            )
            Services = @("DiagTrack", "dmwappushservice")
        }
        Network = @{
            Risk = "High"
            RegistryKeys = @(
                "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters",
                "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces",
                "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters",
                "HKLM\SOFTWARE\Policies\Microsoft\Windows\Psched",
                "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile",
                "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters",
                "HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces"
            )
            Services = @("Dnscache", "NlaSvc", "NetBT")
        }
        Security = @{
            Risk = "High"
            RegistryKeys = @(
                "HKLM\SOFTWARE\Microsoft\Windows Defender",
                "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender",
                "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters",
                "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL"
            )
            Services = @("WinDefend", "mpssvc", "BFE")
        }
        Services = @{
            Risk = "High"
            RegistryKeys = @("HKLM\SYSTEM\CurrentControlSet\Services")
            Services = @("SysMain", "WSearch", "DiagTrack", "dmwappushservice", "wuauserv", "bits", "Spooler")
        }
        Updates = @{
            Risk = "Medium"
            RegistryKeys = @("HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate", "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate")
            Services = @("wuauserv", "bits", "cryptsvc", "UsoSvc")
        }
        Power = @{
            Risk = "Medium"
            RegistryKeys = @("HKLM\SYSTEM\CurrentControlSet\Control\Power", "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings")
            Services = @()
        }
        Apps = @{
            Risk = "Medium"
            RegistryKeys = @("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx", "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall")
            Services = @("AppXSvc", "ClipSVC")
        }
        StartupOptimizer = @{
            Risk = "Medium"
            RegistryKeys = @("HKCU\Software\Microsoft\Windows\CurrentVersion\Run", "HKLM\Software\Microsoft\Windows\CurrentVersion\Run", "HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")
            Services = @("Schedule")
        }
        ComponentCleanup = @{
            Risk = "Medium"
            RegistryKeys = @()
            Services = @("TrustedInstaller")
        }
        EventLogMaintenance = @{
            Risk = "Medium"
            RegistryKeys = @()
            Services = @("EventLog")
        }
        FeatureOptimizer = @{
            Risk = "Medium"
            RegistryKeys = @("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing", "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide")
            Services = @("TrustedInstaller")
        }
        NetworkRepair = @{
            Risk = "Medium"
            RegistryKeys = @("HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters", "HKLM\SYSTEM\CurrentControlSet\Services\WinSock2")
            Services = @("Dnscache", "Dhcp", "NlaSvc")
        }
        DeviceSnapshot = @{
            Risk = "Low"
            RegistryKeys = @()
            Services = @()
        }
        BenchmarkReport = @{
            Risk = "Low"
            RegistryKeys = @()
            Services = @()
        }
        PrivacyReview = @{
            Risk = "Low"
            RegistryKeys = @()
            Services = @()
        }
        NetworkDiagnostics = @{
            Risk = "Low"
            RegistryKeys = @()
            Services = @()
        }
        ContainerHyperVTuning = @{
            Risk = "Medium"
            RegistryKeys = @("HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss")
            Services = @("vmcompute", "LxssManager", "hns")
        }
        ZeroTrustSecurity = @{
            Risk = "Medium"
            RegistryKeys = @("HKLM\SYSTEM\CurrentControlSet\Control\Lsa", "HKLM\SOFTWARE\Microsoft\Windows Defender")
            Services = @("WinDefend", "mpssvc", "BFE")
        }
        GameModeUltra = @{
            Risk = "Medium"
            RegistryKeys = @("HKCU\Software\Microsoft\GameBar", "HKCU\System\GameConfigStore", "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR", "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers")
            Services = @()
        }
        AINPUCaching = @{
            Risk = "Low"
            RegistryKeys = @()
            Services = @()
        }
        StorageTiering = @{
            Risk = "Medium"
            RegistryKeys = @()
            Services = @("defragsvc", "storsvc")
        }
        RemoteReadiness = @{
            Risk = "Low"
            RegistryKeys = @()
            Services = @("WinRM", "sshd", "QEMU-GA")
        }
        UpdateRepair = @{
            Risk = "Medium"
            RegistryKeys = @("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate", "HKLM\SYSTEM\CurrentControlSet\Services")
            Services = @("wuauserv", "bits", "cryptsvc", "msiserver", "TrustedInstaller", "UsoSvc")
        }
        PowerPlanTuning = @{
            Risk = "Medium"
            RegistryKeys = @("HKLM\SYSTEM\CurrentControlSet\Control\Power")
            Services = @()
        }
        SecurityAudit = @{
            Risk = "Low"
            RegistryKeys = @()
            Services = @()
        }
        Profile = @{
            Risk = "Medium"
            RegistryKeys = @("HKLM\SOFTWARE\NeoOptimize")
            Services = @()
        }
        Backup = @{
            Risk = "Low"
            RegistryKeys = @()
            Services = @("VSS")
        }
        ThreatMonitor = @{
            Risk = "Low"
            RegistryKeys = @()
            Services = @("WinDefend", "mpssvc", "EventLog")
        }
        Autoimmune = @{
            Risk = "High"
            RegistryKeys = @("HKLM\SOFTWARE\Microsoft\Windows Defender", "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender")
            Services = @("WinDefend", "mpssvc")
        }
        IntegrityScan = @{
            Risk = "Low"
            RegistryKeys = @()
            Services = @()
        }
        SmartBooster = @{
            Risk = "Medium"
            RegistryKeys = @("HKCU\Software\Microsoft\Windows\CurrentVersion\Run", "HKLM\Software\Microsoft\Windows\CurrentVersion\Run")
            Services = @()
        }
        SmartOptimize = @{
            Risk = "High"
            RegistryKeys = @("HKLM\SYSTEM\CurrentControlSet\Services", "HKLM\SOFTWARE\Policies\Microsoft\Windows", "HKCU\Software\Microsoft\Windows")
            Services = @("SysMain", "WSearch", "DiagTrack", "wuauserv", "bits")
        }
        DeepScan = @{
            Risk = "Low"
            RegistryKeys = @()
            Services = @()
        }
        SystemDiagnostics = @{
            Risk = "Low"
            RegistryKeys = @()
            Services = @()
        }
        WindowsDoctor = @{
            Risk = "Low"
            RegistryKeys = @()
            Services = @()
        }
        WindowsErrorFix = @{
            Risk = "High"
            RegistryKeys = @("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate", "HKLM\SYSTEM\CurrentControlSet\Services")
            Services = @("wuauserv", "bits", "cryptsvc", "msiserver", "TrustedInstaller", "Winmgmt", "EventLog")
        }
        SystemRepair = @{
            Risk = "High"
            RegistryKeys = @("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate", "HKLM\SYSTEM\CurrentControlSet\Services")
            Services = @("wuauserv", "bits", "cryptsvc", "msiserver", "TrustedInstaller")
        }
        DiskRepair = @{
            Risk = "High"
            RegistryKeys = @()
            Services = @("vss", "defragsvc")
        }
        DiskOptimize = @{
            Risk = "Medium"
            RegistryKeys = @()
            Services = @("defragsvc")
        }
        HealthRepair = @{
            Risk = "High"
            RegistryKeys = @("HKLM\SYSTEM\CurrentControlSet\Services", "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate")
            Services = @("wuauserv", "bits", "cryptsvc", "msiserver", "TrustedInstaller")
        }
        NeoUpdate = @{
            Risk = "Medium"
            RegistryKeys = @("HKLM\Software\NeoOptimize", "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoOptimize")
            Services = @("NeoOptimize RMM Agent")
        }
    }

    if ($profiles.ContainsKey($ActionName)) { return $profiles[$ActionName] }
    return @{ Risk = "Medium"; RegistryKeys = @(); Services = @() }
}

function Invoke-NeoActionWithSafety {
    param(
        [string]$ActionName,
        [scriptblock]$ScriptBlock
    )
    $safetyProfile = Get-NeoActionSafetyProfile $ActionName
    Invoke-NeoSafetyWrappedAction `
        -ActionName $ActionName `
        -RiskLevel ([string]$safetyProfile.Risk) `
        -RegistryKeys @($safetyProfile.RegistryKeys) `
        -ServiceNames @($safetyProfile.Services) `
        -ScriptBlock $ScriptBlock
}

#  System Summary Bar with Next-Gen Safeguards & Health Scoring
function Write-SystemBar {
    $os    = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu   = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name
    $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB,1)
    $free  = [math]::Round($os.FreePhysicalMemory/1MB,1)
    $build = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion
    $disk  = Get-PSDrive C | Select-Object @{N="Free";E={[math]::Round($_.Free/1GB,1)}},@{N="Used";E={[math]::Round($_.Used/1GB,1)}}

    # Initialize safeguards and health if not cached
    if ($null -eq $Global:NeoSafeguards) {
        $Global:NeoSafeguards = Get-NeoHardwareSafeguards
    }
    if ($null -eq $Global:NeoHealthResult) {
        $Global:NeoHealthResult = Invoke-NeoHealthScreening -Run $true
    }

    $scoreColor = if ($Global:NeoHealthResult.Score -ge 90) { $Global:GREEN } elseif ($Global:NeoHealthResult.Score -ge 70) { $Global:YELLOW } else { $Global:RED }

    Write-Host "  $($Global:DIM)--------------------------------------------------------------------------------$($Global:RESET)"
    Write-Host "  $($Global:WHITE)$($env:COMPUTERNAME.PadRight(15))$($Global:RESET)  OS: Win $build ($($os.OSArchitecture))   CPU: $($cpu.Trim().Substring(0,[Math]::Min(28,$cpu.Length)))..."
    Write-Host "  RAM: ${free}GB/${ramGB}GB free   Disk C: $($disk.Free)GB free / $($disk.Used)GB used   User: $($env:USERNAME)"
    Write-Host "  $($Global:CYAN)SAFEGUARDS:$($Global:RESET) SSD=$($Global:NeoSafeguards.IsSSD) | Laptop=$($Global:NeoSafeguards.IsLaptop) | VM=$($Global:NeoSafeguards.IsVM) | Battery=$($Global:NeoSafeguards.OnBattery)"
    Write-Host "  $($Global:CYAN)HEALTH SCORE:$($Global:RESET) $scoreColor$($Global:NeoHealthResult.Score)/100 ($($Global:NeoHealthResult.Grade))$($Global:RESET) | $($Global:DIM)Junk: $($Global:NeoHealthResult.JunkMB) MB | Registry Errors: $($Global:NeoHealthResult.RegErrors)$($Global:RESET)"
    Write-Host "  $($Global:DIM)--------------------------------------------------------------------------------$($Global:RESET)"
}

#  Menu Item Renderer 
function Write-MenuItem {
    param($Key, $Icon, $Label, $Desc, $Hot = $false)
    $keyColor  = if ($Hot) { "$($Global:YELLOW)$($Global:BOLD)" } else { $Global:CYAN }
    Write-Host "  ${keyColor}[$Key]$($Global:RESET) $Icon $($Global:WHITE)$($Global:BOLD)$Label$($Global:RESET)"
    Write-Host "       $($Global:DIM)$Desc$($Global:RESET)"
}

function Get-OfficialLinks {
    $links = [ordered]@{
        GitHub = "https://github.com/NeoOptimize/NeoOptimize"
        "HF Space" = "https://huggingface.co/spaces/neooptimize/NeoOptimize"
        E2B = "https://e2b.dev/dashboard/neooptimizeofficial/members"
    }

    $cloudConfig = Join-Path $PSScriptRoot "config\NeoOptimize.Cloud.json"
    if (Test-Path $cloudConfig) {
        try {
            $cfg = Get-Content -Path $cloudConfig -Raw | ConvertFrom-Json
            if ($cfg.github.repo_url) { $links["GitHub"] = [string]$cfg.github.repo_url }
            if ($cfg.huggingface.space_url) { $links["HF Space"] = [string]$cfg.huggingface.space_url }
            if ($cfg.e2b.dashboard_url) { $links["E2B"] = [string]$cfg.e2b.dashboard_url }
        } catch { Write-Verbose $_.Exception.Message }
    }
    return $links
}

function Start-NeoBrowserLink {
    param([string]$Name, [string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) {
        Write-Warn "$Name link belum dikonfigurasi."
        return
    }
    try {
        Start-Process $Url -ErrorAction Stop
        Write-OK "$Name dibuka di browser."
    } catch {
        Write-Warn "Tidak bisa membuka browser untuk $Name. Cek default browser Windows."
    }
}

function Read-NeoRmmConfig {
    $path = Join-Path $PSScriptRoot "config\NeoOptimize.RMM.json"
    $fallback = [PSCustomObject]@{
        candidate_server_urls = @("http://192.168.122.1:3000", "http://127.0.0.1:3000")
        auth = [PSCustomObject]@{ token = ""; email = ""; password = "" }
        update = [PSCustomObject]@{ use_rmm_manifest = $true; manifest_path = "/downloads/neooptimize/manifest"; installer_url = ""; installer_sha256 = ""; package_sha256 = ""; silent_args = "/S" }
    }
    if (-not (Test-Path $path)) { return $fallback }
    try {
        $cfg = Get-Content -Path $path -Raw | ConvertFrom-Json
        if (-not $cfg.candidate_server_urls) { $cfg | Add-Member -NotePropertyName candidate_server_urls -NotePropertyValue $fallback.candidate_server_urls -Force }
        if (-not $cfg.auth) { $cfg | Add-Member -NotePropertyName auth -NotePropertyValue $fallback.auth -Force }
        if (-not $cfg.update) { $cfg | Add-Member -NotePropertyName update -NotePropertyValue $fallback.update -Force }
        return $cfg
    } catch {
        return $fallback
    }
}

function Invoke-NeoRmmJson {
    param([string]$Url, [string]$Method = "Get", [object]$Body = $null, [string]$Token = "", [int]$TimeoutSec = 5)
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) { $headers["Authorization"] = "Bearer $Token" }
    $params = @{ Uri = $Url; Method = $Method; Headers = $headers; TimeoutSec = $TimeoutSec }
    if ($null -ne $Body) {
        $params["ContentType"] = "application/json"
        $params["Body"] = ($Body | ConvertTo-Json -Depth 10)
    }
    Invoke-RestMethod @params
}

function Get-NeoRmmServer {
    param($Config)
    foreach ($url in @($Config.candidate_server_urls)) {
        if ([string]::IsNullOrWhiteSpace([string]$url)) { continue }
        $base = ([string]$url).TrimEnd("/")
        try {
            $health = Invoke-NeoRmmJson -Url ($base + "/health") -TimeoutSec 3
            if ($health.status -eq "ok") { return $base }
        } catch { Write-Verbose $_.Exception.Message }
    }
    return ""
}

function Get-NeoRmmToken {
    param($Config, [string]$ServerUrl)
    if ($Config.auth -and -not [string]::IsNullOrWhiteSpace([string]$Config.auth.token)) { return [string]$Config.auth.token }
    if (-not [string]::IsNullOrWhiteSpace($env:NEOOPTIMIZE_RMM_TOKEN)) { return [string]$env:NEOOPTIMIZE_RMM_TOKEN }

    $email = if ($Config.auth -and $Config.auth.email) { [string]$Config.auth.email } else { $env:NEOOPTIMIZE_RMM_EMAIL }
    $password = if ($Config.auth -and $Config.auth.password) { [string]$Config.auth.password } else { $env:NEOOPTIMIZE_RMM_PASSWORD }
    if ([string]::IsNullOrWhiteSpace($email) -or [string]::IsNullOrWhiteSpace($password)) { return "" }
    try {
        $login = Invoke-NeoRmmJson -Url ($ServerUrl + "/api/v1/auth/login") -Method "Post" -Body @{ email = $email; password = $password } -TimeoutSec 8
        if ($login.token) { return [string]$login.token }
    } catch {
        Write-Warn "Login RMM gagal: $($_.Exception.Message)"
    }
    return ""
}

function Get-NeoRmmUpdateArgs {
    param($Config, [string]$ServerUrl, [string]$Token)
    $silentArgs = if ($Config.update -and $Config.update.silent_args) { [string]$Config.update.silent_args } else { "/S" }
    $installerUrl = if ($Config.update -and $Config.update.installer_url) { [string]$Config.update.installer_url } else { "" }
    $installerSha256 = if ($Config.update -and $Config.update.installer_sha256) { [string]$Config.update.installer_sha256 } else { "" }
    $packageSha256 = if ($Config.update -and $Config.update.package_sha256) { [string]$Config.update.package_sha256 } else { "" }
    $updateToken = ""
    $useManifest = if ($Config.update -and $Config.update.PSObject.Properties.Name -contains "use_rmm_manifest") { [bool]$Config.update.use_rmm_manifest } else { $true }
    $manifestPath = if ($Config.update -and $Config.update.manifest_path) { [string]$Config.update.manifest_path } else { "/downloads/neooptimize/manifest" }

    if ($useManifest) {
        $manifestUrl = if ($manifestPath -match "^https?://") { $manifestPath } else { $ServerUrl.TrimEnd("/") + "/" + $manifestPath.TrimStart("/") }
        $manifest = Invoke-NeoRmmJson -Url $manifestUrl -Token $Token -TimeoutSec 8
        if ($manifest.url) {
            $installerUrl = [string]$manifest.url
            if ($installerUrl -notmatch "^https?://") { $installerUrl = $ServerUrl.TrimEnd("/") + "/" + $installerUrl.TrimStart("/") }
        }
        if ($manifest.installer_url) {
            $installerUrl = [string]$manifest.installer_url
            if ($installerUrl -notmatch "^https?://") { $installerUrl = $ServerUrl.TrimEnd("/") + "/" + $installerUrl.TrimStart("/") }
        }
        if ($manifest.sha256) { $installerSha256 = [string]$manifest.sha256 }
        if ($manifest.installer_sha256) { $installerSha256 = [string]$manifest.installer_sha256 }
        if ($manifest.package_sha256) { $packageSha256 = [string]$manifest.package_sha256 }
        if ($manifest.silent_args) { $silentArgs = [string]$manifest.silent_args }
        $updateToken = if ($manifest.update_token) { [string]$manifest.update_token } else { "" }
    }

    if ([string]::IsNullOrWhiteSpace($installerUrl)) { throw "URL installer update belum dikonfigurasi." }
    if ([string]::IsNullOrWhiteSpace($installerSha256) -and [string]::IsNullOrWhiteSpace($packageSha256)) { throw "Manifest update tidak memiliki SHA-256." }
    return @{
        source = "NeoOptimize.About"
        local_action = "NeoUpdate"
        installer_url = $installerUrl
        installer_sha256 = $installerSha256
        package_sha256 = $packageSha256
        silent_args = $silentArgs
        update_token = $updateToken
    }
}

function Invoke-NeoRmmUpdate {
    $cfg = Read-NeoRmmConfig
    $server = Get-NeoRmmServer $cfg
    if ([string]::IsNullOrWhiteSpace($server)) { Write-Warn "Server RMM tidak terjangkau."; return }
    $token = Get-NeoRmmToken -Config $cfg -ServerUrl $server
    if ([string]::IsNullOrWhiteSpace($token)) { Write-Warn "Auth RMM belum tersedia."; return }

    try {
        $agentResponse = Invoke-NeoRmmJson -Url ($server + "/api/v1/dashboard/agents?limit=100") -Token $token -TimeoutSec 8
        $onlineAgents = @($agentResponse.agents | Where-Object { $_.live_status -eq "online" -or $_.status -eq "online" })
        if ($onlineAgents.Count -eq 0) { Write-Warn "Tidak ada endpoint RMM online."; return }
        $updateArgs = Get-NeoRmmUpdateArgs -Config $cfg -ServerUrl $server -Token $token
        Write-Info "RMM server : $server"
        Write-Info "Endpoint   : $($onlineAgents.Count) online"
        Write-Info "Installer  : $($updateArgs.installer_url)"
        if (-not (Confirm-NeoAction "  Kirim update NeoOptimize via RMM?" $false)) { return }
        $body = @{
            agent_ids = @($onlineAgents | ForEach-Object { [string]$_.id })
            type = "NEOUPDATE"
            args = $updateArgs
            priority = 3
        }
        $result = Invoke-NeoRmmJson -Url ($server + "/api/v1/dashboard/commands/bulk") -Method "Post" -Body $body -Token $token -TimeoutSec 10
        Write-OK "Update NeoOptimize dikirim ke RMM queue. Issued: $($result.issued)"
    } catch {
        Write-Err "Update via RMM gagal: $($_.Exception.Message)"
    }
}

#  Help & Guidelines Screen
function Show-HelpGuide {
    Write-NeoLogo -Compact
    Write-Host ""
    Write-Host "  $($Global:CYAN)$($Global:BOLD)NEOOPTIMIZE TERMINAL GUIDE & HELP$($Global:RESET)"
    Write-Host ""
    Write-Host "  $($Global:WHITE)Format Penggunaan CLI:$($Global:RESET)"
    Write-Host "    powershell -NoProfile -ExecutionPolicy Bypass -File .\NeoOptimize.ps1 [Opsi]"
    Write-Host ""
    Write-Host "  $($Global:WHITE)Opsi CLI:$($Global:RESET)"
    Write-Host "    $($Global:CYAN)-Action <Nama> $($Global:RESET)  Menjalankan modul tertentu secara langsung tanpa menu."
    Write-Host "                       Pilihan: Dashboard, Cleaner, Performance, Privacy, Network,"
    Write-Host "                                Security, Services, Updates, Power, Maintenance,"
    Write-Host "                                DeepScan, SystemDiagnostics, WindowsDoctor, WindowsErrorFix,"
    Write-Host "                                SystemRepair, AIPlan, AIInteractive, AIScriptForge, VoiceCommand, Profile"
    Write-Host "    $($Global:CYAN)-FullAuto      $($Global:RESET)  Menjalankan Safe Care Plan: audit, deep scan, cleaner ringan, dan report."
    Write-Host "    $($Global:CYAN)-AssumeYes     $($Global:RESET)  Otomatis menyetujui prompt low-risk. Tidak berlaku untuk aksi high-risk."
    Write-Host "    $($Global:CYAN)-Enforce       $($Global:RESET)  Izinkan aksi high-risk setelah Anda memahami dampaknya."
    Write-Host "    $($Global:CYAN)-NoPause       $($Global:RESET)  Melewati penekanan tombol jeda di akhir eksekusi."
    Write-Host ""
    Write-Host "  $($Global:WHITE)Fitur Utama & Perintah Shortcut:$($Global:RESET)"
    Write-Host "    $($Global:CYAN)/help / H      $($Global:RESET)  Menampilkan panduan bantuan terminal ini."
    Write-Host "    $($Global:CYAN)P             $($Global:RESET)  Masuk ke menu Next-Gen Profile Selector (Work, Gaming, General)."
    Write-Host "    $($Global:CYAN)A             $($Global:RESET)  Menjalankan Safe Care Plan dengan restore point, audit, scan, dan cleanup ringan."
    Write-Host ""
    Write-Host "  $($Global:DIM)Development: Zenthralix-lab with Codex.$($Global:RESET)"
    Write-Host "  $($Global:DIM)Support Email    : neooptimizeofficial@gmail.com$($Global:RESET)"
    Write-Host "  $($Global:DIM)Support Links     : Buy Me a Coffee / Saweria / Dana (pilih opsi [I])$($Global:RESET)"
    Write-Host ""
}

#  About Screen
function Show-About {
    Write-NeoLogo
    Write-Host ""
    Write-Host "  $($Global:CYAN)$($Global:BOLD)  NEOOPTIMIZE INFO$($Global:RESET)"
    Write-Host ""
    Write-Host "  $($Global:WHITE)Version  :$($Global:RESET) $($Global:PRODUCT_VERSION)"
    Write-Host "  $($Global:WHITE)Platform :$($Global:RESET) Windows 10 / 11 (PowerShell 5.1+)"
    Write-Host "  $($Global:WHITE)Mode     :$($Global:RESET) Administrator endpoint repair console"
    Write-Host ""
    Write-Host "  $($Global:GREEN)$($Global:BOLD)  Development: Zenthralix-lab with Codex.$($Global:RESET)"
    Write-Host "  $($Global:YELLOW)$($Global:BOLD)  Support: Don't forget to use /help for guidelines on using NeoOptimize.$($Global:RESET)"
    Write-Host ""
    Write-Host "  $($Global:CYAN)Official Email  :$($Global:RESET) neooptimizeofficial@gmail.com"
    Write-Host "  $($Global:CYAN)Support Development:$($Global:RESET)"
    Write-Host "    - Buy Me a Coffee: https://buymeacoffee.com/nol.eight"
    Write-Host "    - Saweria     : https://saweria.co/dtechtive"
    Write-Host "    - Dana        : https://ik.imagekit.io/dtechtive/Dana"
    Write-Host ""
    Write-Separator "" $Global:DIM
    Write-Host ""
    Write-Host "  $($Global:DIM)Terminal Windows VM tidak nyaman untuk copy-paste link.$($Global:RESET)"
    Write-Host "  $($Global:DIM)Pilih aksi di bawah ini agar NeoOptimize membuka browser/folder langsung.$($Global:RESET)"
    Write-Host ""
    $links = Get-OfficialLinks
    Write-Host "  $($Global:CYAN)[1]$($Global:RESET) Open GitHub repository"
    Write-Host "  $($Global:CYAN)[2]$($Global:RESET) Open support email"
    Write-Host "  $($Global:CYAN)[3]$($Global:RESET) Open update assistant"
    Write-Host "  $($Global:CYAN)[4]$($Global:RESET) Open reports folder"
    Write-Host "  $($Global:CYAN)[5]$($Global:RESET) Open Buy Me a Coffee"
    Write-Host "  $($Global:CYAN)[6]$($Global:RESET) Open Saweria Support"
    Write-Host "  $($Global:CYAN)[7]$($Global:RESET) Open Dana Support"
    Write-Host "  $($Global:CYAN)[8]$($Global:RESET) Update NeoOptimize"
    Write-Host "  $($Global:CYAN)[0]$($Global:RESET) Kembali"
    Write-Host ""
    $aboutChoice = Read-NeoChoice "  Pilihan [0-8]" @("0","1","2","3","4","5","6","7","8") "0"
    switch ($aboutChoice) {
        "1" { Start-NeoBrowserLink "GitHub" $links["GitHub"] }
        "2" { Start-NeoBrowserLink "Email" "mailto:neooptimizeofficial@gmail.com" }
        "3" { Start-NeoBrowserLink "Update Assistant" "https://github.com/NeoOptimize/NeoOptimize/releases" }
        "4" {
            if (-not (Test-Path $Global:LogFile)) { Write-Err "Log file tidak ditemukan."; return }
            Start-Process notepad.exe -ArgumentList "`"$Global:LogFile`""
            Write-OK "Log file dibuka di Notepad."
        }
        "5" { Start-NeoBrowserLink "Buy Me a Coffee" "https://buymeacoffee.com/nol.eight" }
        "6" { Start-NeoBrowserLink "Saweria" "https://saweria.co/dtechtive" }
        "7" { Start-NeoBrowserLink "Dana" "https://ik.imagekit.io/dtechtive/Dana" }
        "8" { Invoke-NeoRmmUpdate }
        default { return }
    }
    Wait-AnyKey "Tekan tombol apapun untuk kembali ke menu utama..."
}

#  Status Dashboard 
function Show-Dashboard {
    Write-NeoLogo -Compact
    Write-SectionHeader "" "SYSTEM DASHBOARD" "Real-time system status"

    $snap = Get-SystemSnapshot

    # System Info Grid
    $info = @(
        @(" Computer",   $snap.ComputerName),
        @(" User",       $snap.User),
        @(" Windows",    "$($snap.OS) [Build $($snap.OSBuild)]"),
        @("  CPU",        $snap.CPU),
        @(" Cores",      "$($snap.CPUCores) cores / $($snap.CPUThreads) threads"),
        @(" RAM",        "$($snap.RAMFree) GB free / $($snap.RAMTotal) GB total"),
        @(" GPU",        $snap.GPU),
        @("  Uptime",     "$($snap.Uptime.Days)d $($snap.Uptime.Hours)h $($snap.Uptime.Minutes)m"),
        @(" Model",      "$($snap.Manufacturer) $($snap.Model)"),
        @(" BIOS",       $snap.BIOSVersion)
    )
    foreach ($item in $info) {
        Write-Host "  $($Global:CYAN)$($item[0].PadRight(14))$($Global:RESET) $($item[1])"
    }

    Write-Host ""
    Write-Separator "" $Global:DIM

    # Disk Usage
    Write-Host ""
    Write-Step "DISK USAGE"
    Write-Host ""
    Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 } | ForEach-Object {
        $total  = [math]::Round(($_.Used + $_.Free) / 1GB, 1)
        $used   = [math]::Round($_.Used / 1GB, 1)
        $free   = [math]::Round($_.Free / 1GB, 1)
        $pct    = [math]::Round(($_.Used / ($_.Used + $_.Free)) * 100)
        $fill   = [math]::Round($pct / 5)
        $bar    = "" * $fill + "" * (20 - $fill)
        $color  = if ($pct -gt 90) { $Global:RED } elseif ($pct -gt 75) { $Global:YELLOW } else { $Global:GREEN }
        Write-Host "  $($Global:WHITE)[$($_.Name):]$($Global:RESET)  $color$bar$($Global:RESET)  $pct%  $($Global:DIM)${used}GB / ${total}GB (${free}GB free)$($Global:RESET)"
    }

    Write-Host ""
    Write-Separator "" $Global:DIM

    # Top Processes
    Write-Host ""
    Write-Step "TOP 5 PROSES (CPU)"
    Write-Host ""
    Write-Host "  $($Global:DIM)$("NAMA".PadRight(28)) $("CPU(s)".PadRight(10)) $("RAM(MB)".PadRight(10)) PID$($Global:RESET)"
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | ForEach-Object {
        $cpuS = [math]::Round($_.CPU, 1)
        $ramM = [math]::Round($_.WorkingSet / 1MB, 0)
        Write-Host "  $($_.Name.PadRight(28)) $("$cpuS".PadRight(10)) $("$ramM".PadRight(10)) $($_.Id)"
    }

    Write-Host ""
    Wait-AnyKey
}

#  Safe Care Plan (legacy -FullAuto entry point)
function Invoke-FullGodMode {
    Write-NeoLogo
    Write-Host ""
    Write-Host "  $($Global:CYAN)$($Global:BOLD)  $($Global:RESET)"
    Write-Host "  $($Global:CYAN)$($Global:BOLD)     SAFE CARE PLAN  AUDIT-FIRST WINDOWS MAINTENANCE     $($Global:RESET)"
    Write-Host "  $($Global:CYAN)$($Global:BOLD)  $($Global:RESET)"
    Write-Host ""
    Write-Host "  $($Global:YELLOW)Modul aman yang akan berjalan:$($Global:RESET)"
    Write-Host "  $($Global:DIM)  24 Device Snapshot  25 Benchmark  26 Privacy Review  27 Network Diagnostics$($Global:RESET)"
    Write-Host "  $($Global:DIM)  16 System Diagnostics  15 Deep Scan  01 Cleaner  Agent Audit$($Global:RESET)"
    Write-Host ""
    Write-Host "  $($Global:YELLOW)Tidak menjalankan Performance/Privacy/Services/Security/Power high-risk tanpa -Enforce.$($Global:RESET)"
    Write-Host ""

    if (-not $Global:NeoOptimizeAssumeYes) {
        $confirm = Read-Host "  Ketik 'YES' untuk menjalankan Safe Care Plan"
        if ($confirm -ne "YES") {
            Write-Warn "Dibatalkan."
            Wait-AnyKey; return
        }
    } else {
        Write-Info "AssumeYes aktif: hanya modul low-risk Safe Care yang dijalankan."
    }

    Write-Info "Membuat System Restore Point sebelum perawatan aman..."
    New-RestorePoint "NeoOptimize Safe Care Plan  $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

    $prevNonInteractive = $Global:NeoOptimizeNonInteractive
    $prevSkipPause = $Global:NeoOptimizeSkipPause
    $Global:NeoOptimizeNonInteractive = $true
    $Global:NeoOptimizeSkipPause = $true

    $modules = @(
        @{File="24_DeviceSnapshot.ps1";     Icon="HW"; Name="Device Snapshot"},
        @{File="25_BenchmarkReport.ps1";    Icon="BENCH"; Name="Benchmark Baseline"},
        @{File="26_PrivacyReview.ps1";      Icon="PRV"; Name="Privacy Review"},
        @{File="27_NetworkDiagnostics.ps1"; Icon="NET"; Name="Network Diagnostics"},
        @{File="16_SystemDiagnostics.ps1"; Icon=""; Name="System Diagnostics"},
        @{File="18_NeoWindowsDoctor.ps1"; Icon="NEO"; Name="NEO Windows Doctor"},
        @{File="15_DeepScan.ps1";          Icon=""; Name="Deep Scan"},
        @{File="01_Cleaner.ps1";           Icon=""; Name="System Cleaner"}
    )

    try {
        $total = $modules.Count
        $i = 0
        foreach ($m in $modules) {
            $i++
            Write-Host ""
            Write-Host "  $($Global:MAGENTA)$($Global:BOLD)[$i/$total] $($m.Icon) $($m.Name)$($Global:RESET)"
            Write-Separator "" $Global:DIM
            $path = "$PSScriptRoot\modules\$($m.File)"
            if (Test-Path $path) {
                try { . $path } catch { Write-Warn "Error di modul $($m.File): $($_.Exception.Message)" }
            } else {
                Write-Err "Modul tidak ditemukan: $($m.File)"
            }
        }
    } finally {
        $Global:NeoOptimizeNonInteractive = $prevNonInteractive
        $Global:NeoOptimizeSkipPause = $prevSkipPause
    }

    # Generate HTML Report
    Write-Host ""
    Write-Info "Membuat laporan HTML..."
    $reportPath = "$PSScriptRoot\reports\SafeCare_$(Get-Date -f 'yyyyMMdd_HHmmss').html"
    $logEntries = $Global:LogBuf | ForEach-Object {
        $parts = $_ -split '\]\[|\[|\]'
        $level = if ($parts.Count -ge 3) { ConvertTo-HtmlSafe $parts[2] } else { "INFO" }
        $msg   = if ($parts.Count -ge 4) { ConvertTo-HtmlSafe $parts[3] } else { ConvertTo-HtmlSafe $_ }
        "<div class='entry'><span class='badge $level'>$level</span><span>$msg</span></div>"
    }
    $sections = "<div class='card'><h2> Log Optimasi</h2>$($logEntries -join '')</div>"
    if (Export-HtmlReport "Safe Care Plan Report" $sections $reportPath) {
        Write-OK "Laporan HTML: $reportPath"
    }

    $agentPath = Join-Path $PSScriptRoot "NeoOptimizeAgent.ps1"
    if (Test-Path $agentPath) {
        Write-Info "Menjalankan NeoOptimize Agent post-audit..."
        try {
            & $agentPath -Mode Audit -Quiet -NoOpen
            Write-OK "Agent post-audit selesai. Cek folder reports\agent."
        } catch {
            Write-Warn "Agent post-audit gagal: $($_.Exception.Message)"
        }
    }

    Write-Host ""
    Write-Host "  $($Global:GREEN)$($Global:BOLD)  $($Global:RESET)"
    Write-Host "  $($Global:GREEN)$($Global:BOLD)     SAFE CARE PLAN SELESAI  LAPORAN SIAP DIREVIEW     $($Global:RESET)"
    Write-Host "  $($Global:GREEN)$($Global:BOLD)  $($Global:RESET)"
    Write-Host ""
    Write-Host "  $($Global:YELLOW)Untuk tuning agresif, jalankan modul spesifik dengan -Enforce setelah review AI Doctor.$($Global:RESET)"
    Write-Host ""
    Wait-AnyKey
}

# 
#   MAIN MENU LOOP
# 
function Invoke-ActionMode {
    param([string]$Name)

    switch ($Name) {
        "Dashboard"       { Show-Dashboard }
        "Permissions"     { Invoke-Module "00_Permissions.ps1" }
        "Cleaner"         { Invoke-Module "01_Cleaner.ps1" }
        "Performance"     { Invoke-Module "02_Performance.ps1" }
        "Privacy"         { Invoke-Module "03_Privacy.ps1" }
        "Network"         { Invoke-Module "04_Network.ps1" }
        "Security"        { Invoke-Module "05_Security.ps1" }
        "DefenderAuditMode" { Invoke-DefenderAuditMode }
        "Collect"         { Invoke-Module "06_Collect.ps1" }
        "Services"        { Invoke-Module "06_Services.ps1" }
        "Updates"         { Invoke-Module "07_Updates.ps1" }
        "Power"           { Invoke-Module "08_Power.ps1" }
        "Apps"            { Invoke-Module "09_Apps.ps1" }
        "StartupOptimizer" { Invoke-Module "19_StartupOptimizer.ps1" }
        "ComponentCleanup" { Invoke-Module "20_ComponentCleanup.ps1" }
        "EventLogMaintenance" { Invoke-Module "21_EventLogMaintenance.ps1" }
        "FeatureOptimizer" { Invoke-Module "22_WindowsFeatureOptimizer.ps1" }
        "NetworkRepair"   { Invoke-Module "23_NetworkRepairToolkit.ps1" }
        "DeviceSnapshot"   { Invoke-Module "24_DeviceSnapshot.ps1" }
        "BenchmarkReport"  { Invoke-Module "25_BenchmarkReport.ps1" }
        "PrivacyReview"    { Invoke-Module "26_PrivacyReview.ps1" }
        "NetworkDiagnostics" { Invoke-Module "27_NetworkDiagnostics.ps1" }
        "ContainerHyperVTuning" { Invoke-Module "28_ContainerHyperVTuning.ps1" }
        "ZeroTrustSecurity" { Invoke-Module "29_ZeroTrustSecurity.ps1" }
        "GameModeUltra"    { Invoke-Module "30_GameModeUltra.ps1" }
        "AINPUCaching"     { Invoke-Module "31_AINPUCaching.ps1" }
        "StorageTiering"   { Invoke-Module "32_StorageTiering.ps1" }
        "RemoteReadiness"  { Invoke-Module "33_RemoteAccessReadiness.ps1" }
        "UpdateRepair"     { Invoke-Module "34_UpdateRepair.ps1" }
        "PowerPlanTuning"  { Invoke-Module "35_PowerPlanTuning.ps1" }
        "SecurityAudit"    { Invoke-Module "36_SecurityAudit.ps1" }
        "Maintenance"     { Invoke-MaintenanceModule "Menu" }
        "CleanAll"        { Invoke-MaintenanceModule "CleanAll" }
        "ScheduleClean"   { Invoke-MaintenanceModule "ScheduleClean" }
        "SmartBooster"    { Invoke-MaintenanceModule "SmartBooster" }
        "SmartOptimize"   { Invoke-MaintenanceModule "SmartOptimize" }
        "Profile"         { Invoke-Module "10_Profile.ps1" }
        "Backup"          { Invoke-Module "11_Backup.ps1" }
        "ThreatMonitor"   { Invoke-Module "12_ThreatMonitor.ps1" }
        "Autoimmune"      { Invoke-Module "13_Autoimmune.ps1" }
        "IntegrityScan"   { Invoke-Module "14_IntegrityScan.ps1" }
        "DeepScan"        { Invoke-Module "15_DeepScan.ps1" }
        "SystemDiagnostics" { Invoke-Module "16_SystemDiagnostics.ps1" }
        "WindowsDoctor"   { Invoke-NeoActionWithSafety "WindowsDoctor" { & (Join-Path $PSScriptRoot "modules\18_NeoWindowsDoctor.ps1") -Mode Scan } }
        "WindowsErrorFix" { Invoke-NeoActionWithSafety "WindowsErrorFix" { & (Join-Path $PSScriptRoot "modules\18_NeoWindowsDoctor.ps1") -Mode Fix } }
        "SystemRepair"    { Invoke-Module "10_SystemRepair.ps1" }
        "DiskStatus"      { Invoke-MaintenanceModule "DiskStatus" }
        "DiskScan"        { Invoke-MaintenanceModule "DiskScan" }
        "DiskRepair"      { Invoke-MaintenanceModule "DiskRepair" }
        "DiskOptimize"    { Invoke-MaintenanceModule "DiskOptimize" }
        "HealthRepair"    { Invoke-MaintenanceModule "HealthRepair" }
        "RestorePoint"    {
            Write-Info "Membuat System Restore Point..."
            New-RestorePoint "NeoOptimize Manual Backup  $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            Wait-AnyKey
        }
        "RollbackLast"    {
            Invoke-NeoLastLocalRollback | Out-Null
            Wait-AnyKey
        }
        "FreeAgent"       { & (Join-Path $PSScriptRoot "NeoOptimize.AIAgent.ps1") -Mode Analyze }
        "FreeAgentProviders" { & (Join-Path $PSScriptRoot "NeoOptimize.AIAgent.ps1") -Mode Providers }
        "NullClawDocs"      { & (Join-Path $PSScriptRoot "NeoOptimize.AIAgent.ps1") -Mode OpenNullClawDocs }
        "AIPlan"          { & (Join-Path $PSScriptRoot "NeoOptimize.AIAgent.ps1") -Mode Plan }
        "AIInteractive"   { & (Join-Path $PSScriptRoot "NeoOptimize.AIAgent.ps1") -Mode Interactive }
        "NEOAgentic"      { & (Join-Path $PSScriptRoot "NeoOptimize.AgenticRunner.ps1") -Mode RunOnce }
        "AIScriptForge"   { & (Join-Path $PSScriptRoot "NeoOptimize.AIAgent.ps1") -Mode ScriptForge }
        "AICatalog"       { & (Join-Path $PSScriptRoot "NeoOptimize.AIAgent.ps1") -Mode Catalog }
        "AIProviders"     { & (Join-Path $PSScriptRoot "NeoOptimize.AIAgent.ps1") -Mode Providers }
        "AIEnvironment"   { & (Join-Path $PSScriptRoot "NeoOptimize.AIAgent.ps1") -Mode Environment }
        "AITrain"         { & (Join-Path $PSScriptRoot "NeoOptimize.AIAgent.ps1") -Mode TrainNeoCore }
        "LocalAISetup"    { & (Join-Path $PSScriptRoot "NeoOptimize.AIAgent.ps1") -Mode LocalAISetup }
        "VoiceCommand"    { & (Join-Path $PSScriptRoot "NeoOptimize.VoiceCommand.ps1") }
        "CloudStatus"     { & (Join-Path $PSScriptRoot "NeoOptimize.Cloud.ps1") -Mode Status }
        "CloudOpen"       { & (Join-Path $PSScriptRoot "NeoOptimize.Cloud.ps1") -Mode Open }
        "AgentAudit"      { & (Join-Path $PSScriptRoot "NeoOptimizeAgent.ps1") -Mode Audit }
        "AgentRemediate"  { & (Join-Path $PSScriptRoot "NeoOptimizeAgent.ps1") -Mode Remediate -AssumeYes }
        "AgentInstall"    { & (Join-Path $PSScriptRoot "NeoOptimizeAgent.ps1") -Mode Install -AssumeYes }
        "AgentStatus"     { & (Join-Path $PSScriptRoot "NeoOptimizeAgent.ps1") -Mode Status }
        "AgentUninstall"  { & (Join-Path $PSScriptRoot "NeoOptimizeAgent.ps1") -Mode Uninstall -AssumeYes }
        "RemoteAccess"    { & (Join-Path $PSScriptRoot "tools\Enable-NeoOptimizeRemoteAccess.ps1") -Mode Status }
        "NeoUpdate"       { Invoke-NeoActionWithSafety "NeoUpdate" { & (Join-Path $PSScriptRoot "NeoOptimize.UpdateManager.ps1") -Mode Update } }
    }
}

function Invoke-DefenderAuditMode {
    Write-ModuleHeader "DF" "" "DEFENDER LAB RECOVERY"
    Write-Warn "Mode ini untuk recovery VM/lab setelah hardening lama membuat Windows Security terlalu ketat."
    Write-Info "Defender realtime, antivirus, firewall, dan cloud protection tetap aktif."
    Write-Info "Yang diubah: Controlled Folder Access, Network Protection, dan ASR rule kustom menjadi AuditMode."
    Write-Host ""

    $defBefore = Get-MpComputerStatus -ErrorAction SilentlyContinue
    $prefBefore = Get-MpPreference -ErrorAction SilentlyContinue
    Write-Host "  Defender realtime       : $($defBefore.RealTimeProtectionEnabled)"
    Write-Host "  Network Protection      : $($prefBefore.EnableNetworkProtection)"
    Write-Host "  Controlled Folder Access: $($prefBefore.EnableControlledFolderAccess)"
    Write-Host "  ASR rules configured    : $(@($prefBefore.AttackSurfaceReductionRules_Ids).Count)"
    Write-Host ""

    if (-not (Confirm-NeoAction "  Lanjut pindahkan policy agresif lab ke AuditMode?" $false)) {
        Write-Info "Dibatalkan. Tidak ada policy Defender yang diubah."
        Wait-AnyKey
        return
    }

    try {
        Set-MpPreference -EnableControlledFolderAccess AuditMode -ErrorAction Stop
        Write-OK "Controlled Folder Access: AuditMode"
    } catch {
        Write-Warn "Controlled Folder Access tidak berubah: $($_.Exception.Message)"
    }

    try {
        Set-MpPreference -EnableNetworkProtection AuditMode -ErrorAction Stop
        Write-OK "Network Protection: AuditMode"
    } catch {
        Write-Warn "Network Protection tidak berubah: $($_.Exception.Message)"
    }

    try {
        $pref = Get-MpPreference -ErrorAction Stop
        $ids = @($pref.AttackSurfaceReductionRules_Ids)
        if ($ids.Count -gt 0) {
            $actions = @()
            for ($i = 0; $i -lt $ids.Count; $i++) { $actions += "AuditMode" }
            Set-MpPreference -AttackSurfaceReductionRules_Ids $ids -AttackSurfaceReductionRules_Actions $actions -ErrorAction Stop
            Write-OK "Configured ASR rules: AuditMode"
        } else {
            Write-Info "Tidak ada ASR rule kustom yang perlu dipulihkan."
        }
    } catch {
        Write-Warn "ASR tidak berubah: $($_.Exception.Message)"
    }

    $prefAfter = Get-MpPreference -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "  Network Protection      : $($prefAfter.EnableNetworkProtection)"
    Write-Host "  Controlled Folder Access: $($prefAfter.EnableControlledFolderAccess)"
    Write-Host "  ASR rules configured    : $(@($prefAfter.AttackSurfaceReductionRules_Ids).Count)"
    Write-Host ""
    Write-OK "Recovery selesai. Coba ulang installer/aksi yang sebelumnya diblok Windows Security."
    Wait-AnyKey
}

if ($Action) {
    Invoke-ActionMode $Action
    exit 0
}

if ($FullAuto) {
    Invoke-FullGodMode
    exit 0
}

while ($true) {
    Write-NeoLogo
    Write-SystemBar
    Write-Host ""
    Write-Host "  $($Global:MAGENTA)$($Global:BOLD) MENU UTAMA  PILIH MODUL$($Global:RESET)"
    Write-Host ""

    Write-MenuItem "0" "" "System Dashboard"          "Real-time info CPU, RAM, Disk, proses aktif"
    Write-MenuItem "1" "" "System Cleaner"            "Hapus junk, temp, cache, prefetch, WER, DNS, browser"
    Write-MenuItem "2" "" "Performance Optimizer"     "RAM flush, visual effects, pagefile, NTFS, boot"
    Write-MenuItem "3" "" "Privacy & Telemetry"       "Matikan telemetri, Cortana, tracking, bloatware"
    Write-MenuItem "4" "" "Network Optimizer"         "TCP/IP, DNS pilihan, QoS, Nagle, hosts file"
    Write-MenuItem "5" "" "Security Audit / Hardening" "Audit-first; hardening butuh ENFORCE eksplisit"
    Write-MenuItem "6" "" "Services Manager"          "5 profil: Home / Gaming / Workstation / Minimal / Restore"
    Write-MenuItem "7" "" "Update & Driver Manager"   "Kontrol update, audit driver, winget upgrade"
    Write-MenuItem "8" "" "Power & Gaming Mode"       "Ultimate power plan, GPU boost, mouse latency"
    Write-MenuItem "9" "" "NeoOptimize Agent"          "Audit otomatis, scoring, report, remediation aman"
    Write-MenuItem "N" "" "NeoCore AI Plan"            "Model AI lokal memberi urutan modul, risk, confidence, dan RMM mapping"
    Write-MenuItem "O" "" "NEO Agentic Autopilot"      "Observe, plan, approve, act, verify, learn dengan konfirmasi manusia"
    Write-MenuItem "V" "" "Voice Command"              "Kontrol NeoOptimize dengan perintah suara lokal Windows"
    Write-MenuItem "M" "" "Maintenance Manager"        "Scheduled cleanup, deep scan, diagnostics, repair, disk scan/repair, defrag/TRIM"
    Write-MenuItem "B" "" "Debloat App Uninstaller"    "Pilih aplikasi bawaan Windows yang ingin dihapus"
    Write-MenuItem "S" "" "Startup Optimizer"          "Audit/disable startup Run entries dan scheduled tasks"
    Write-MenuItem "C" "" "Component Store Cleanup"    "Audit WinSxS dan DISM StartComponentCleanup"
    Write-MenuItem "E" "" "Event Log Maintenance"      "Export log EVTX, optional clear setelah backup"
    Write-MenuItem "F" "" "Windows Feature Optimizer"  "Audit/disable optional legacy features"
    Write-MenuItem "T" "" "Network Repair Toolkit"     "Flush DNS, renew DHCP, reset proxy/Winsock"
    Write-MenuItem "21" "" "Device Snapshot"           "Inventaris hardware, driver, disk, BitLocker, TPM, Secure Boot"
    Write-MenuItem "22" "" "Before/After Benchmark"    "Capture baseline dan after report performa"
    Write-MenuItem "23" "" "Privacy Review"            "Audit privacy tanpa mengunci kamera, mic, location"
    Write-MenuItem "24" "" "Network Diagnostics"       "Test konektivitas, DNS, route, TCP setting"
    Write-MenuItem "25" "" "Container/Hyper-V Tuning"  "Audit WSL2/Hyper-V dan tulis .wslconfig bila disetujui"
    Write-MenuItem "26" "" "Zero-Trust Security"       "ASR audit mode dan hardening terkonfirmasi"
    Write-MenuItem "27" "" "Game Mode Ultra"           "Game Mode/HAGS/GameDVR audit dan tuning aman"
    Write-MenuItem "28" "" "AI & NPU Caching"          "Inventaris NPU/GPU dan policy batas cache AI"
    Write-MenuItem "29" "" "NVMe DirectStorage"        "Audit BypassIO, ReTrim, storage tiering"
    Write-MenuItem "30" "" "Remote Access Readiness"   "Cek WinRM/OpenSSH/RDP/QEMU/RMM tanpa membuka akses"
    Write-MenuItem "31" "" "Windows Update Repair"     "DISM/SFC dan reset update component terkonfirmasi"
    Write-MenuItem "32" "" "Power Plan Tuning"         "Audit powercfg dan pilih power plan"
    Write-MenuItem "33" "" "Security Audit"            "Audit Defender, firewall, TPM, BitLocker, UAC, SMB"
    Write-MenuItem "P" "" "Select System Profile"      "Ganti mode penggunaan: Work / Gaming / General"
    Write-Host ""
    Write-MenuItem "R" "" "Buat Restore Point"         "System Restore Point sebelum optimasi"
    Write-MenuItem "L" "" "Rollback Local Terakhir"    "Pulihkan registry/service dari safety transaction terakhir"
    Write-MenuItem "D" "" "Defender Lab Recovery"      "Pulihkan CFA/ASR/NetworkProtection ke AuditMode setelah hardening lama"
    Write-MenuItem "A" "" "Safe Care Plan"             "Audit, deep scan, cleaner ringan, dan report" -Hot $true
    Write-MenuItem "I" "" "Info & Links"               "Open GitHub, support, update assistant, or reports folder"
    Write-MenuItem "Q" "" "Keluar"                     "Tutup NeoOptimize"
    Write-Host ""
    Write-Footer
    Write-Host ""

    $choice = Read-Host "  $($Global:CYAN)$($Global:BOLD)Pilihan Anda$($Global:RESET)"

    switch ($choice.ToUpper().Trim()) {
        "0" { Show-Dashboard }
        "1" { Invoke-Module "01_Cleaner.ps1" }
        "2" { Invoke-Module "02_Performance.ps1" }
        "3" { Invoke-Module "03_Privacy.ps1" }
        "4" { Invoke-Module "04_Network.ps1" }
        "5" { Invoke-Module "05_Security.ps1" }
        "6" { Invoke-Module "06_Services.ps1" }
        "7" { Invoke-Module "07_Updates.ps1" }
        "8" { Invoke-Module "08_Power.ps1" }
        "9" { Invoke-AgentConsole }
        "N" { & (Join-Path $PSScriptRoot "NeoOptimize.AIAgent.ps1") -Mode Plan }
        "O" { & (Join-Path $PSScriptRoot "NeoOptimize.AgenticRunner.ps1") -Mode RunOnce }
        "V" { & (Join-Path $PSScriptRoot "NeoOptimize.VoiceCommand.ps1") }
        "M" { Invoke-MaintenanceModule "Menu" }
        "B" { Invoke-Module "09_Apps.ps1" }
        "S" { Invoke-Module "19_StartupOptimizer.ps1" }
        "C" { Invoke-Module "20_ComponentCleanup.ps1" }
        "E" { Invoke-Module "21_EventLogMaintenance.ps1" }
        "F" { Invoke-Module "22_WindowsFeatureOptimizer.ps1" }
        "T" { Invoke-Module "23_NetworkRepairToolkit.ps1" }
        "21" { Invoke-Module "24_DeviceSnapshot.ps1" }
        "22" { Invoke-Module "25_BenchmarkReport.ps1" }
        "23" { Invoke-Module "26_PrivacyReview.ps1" }
        "24" { Invoke-Module "27_NetworkDiagnostics.ps1" }
        "25" { Invoke-Module "28_ContainerHyperVTuning.ps1" }
        "26" { Invoke-Module "29_ZeroTrustSecurity.ps1" }
        "27" { Invoke-Module "30_GameModeUltra.ps1" }
        "28" { Invoke-Module "31_AINPUCaching.ps1" }
        "29" { Invoke-Module "32_StorageTiering.ps1" }
        "30" { Invoke-Module "33_RemoteAccessReadiness.ps1" }
        "31" { Invoke-Module "34_UpdateRepair.ps1" }
        "32" { Invoke-Module "35_PowerPlanTuning.ps1" }
        "33" { Invoke-Module "36_SecurityAudit.ps1" }
        "P" { Invoke-Module "10_Profile.ps1" }
        "HELP"  { Show-HelpGuide; Wait-AnyKey }
        "/HELP" { Show-HelpGuide; Wait-AnyKey }
        "H"     { Show-HelpGuide; Wait-AnyKey }
        "R" { 
            Write-Info "Membuat System Restore Point..."
            New-RestorePoint "NeoOptimize Manual Backup  $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            Wait-AnyKey
        }
        "L" {
            Invoke-NeoLastLocalRollback | Out-Null
            Wait-AnyKey
        }
        "D" { Invoke-DefenderAuditMode }
        "A" { Invoke-FullGodMode }
        "I" { Show-About }
        "Q" {
            Write-NeoLogo -Compact
            Write-Host ""
            Write-Host "  $($Global:GREEN)Terima kasih telah menggunakan NeoOptimize!$($Global:RESET)"
            Write-Host "  $($Global:DIM)Log tersimpan di: $($Global:LogFile)$($Global:RESET)"
            Write-Footer
            Write-Host ""
            exit 0
        }
        default {
            Write-Warn "Pilihan tidak valid: '$choice'"
            Start-Sleep 1
        }
    }
}
