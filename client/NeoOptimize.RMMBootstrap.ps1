#Requires -Version 5.1

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $Root "config\NeoOptimize.RMM.json"
$AgentDir = Join-Path $Root "rmm-agent"
$Installer = Join-Path $AgentDir "NeoOptimize.Agent.Install.ps1"
$LogDir = Join-Path $Root "reports\rmm"
$LogPath = Join-Path $LogDir "RMMBootstrap_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

function Write-BootstrapLog {
    param([string]$Message)
    Add-Content -Path $LogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

function Test-BootstrapAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Start-ElevatedBootstrap {
    $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $psExe)) { $psExe = "powershell.exe" }
    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "RemoteSigned",
        "-File", "`"$PSCommandPath`""
    )
    Write-BootstrapLog "Bootstrap is not elevated. Relaunching with administrator privileges."
    try {
        $proc = Start-Process -FilePath $psExe -ArgumentList $args -Verb RunAs -Wait -PassThru
        if ($proc -and $proc.ExitCode -ne $null) {
            Write-BootstrapLog "Elevated bootstrap exited with code: $($proc.ExitCode)"
            exit ([int]$proc.ExitCode)
        }
        Write-BootstrapLog "Elevated bootstrap finished without an exit code."
        exit 0
    } catch {
        Write-BootstrapLog "Failed to relaunch elevated bootstrap: $($_.Exception.Message)"
        exit 1
    }
}

function Read-RmmConfig {
    if (Test-Path $ConfigPath) {
        try { return Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json } catch {}
    }
    return [PSCustomObject]@{
        auto_install_agent = $true
        service_name = "NeoOptimize RMM Agent"
        agent_install_dir = "%ProgramFiles%\NeoOptimize\Agent"
        candidate_server_urls = @("http://192.168.122.1:3000", "http://10.10.10.1:3000", "http://192.168.1.9:3000", "http://10.0.2.2:3000", "http://127.0.0.1:3000")
        enrollment_token = ""
        telemetry = [PSCustomObject]@{
            collect_device_capabilities = $true
            collect_approx_location = $false
            collect_verbose_diagnostics = $false
        }
    }
}

function Test-RmmUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    try {
        $health = Invoke-RestMethod -Uri ($Url.TrimEnd("/") + "/health") -Method Get -TimeoutSec 4
        return [bool]($health.status -eq "ok")
    } catch {
        return $false
    }
}

function Expand-NeoPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Get-InstalledAgentServerUrl {
    param([string]$InstallDir)
    $settings = Join-Path $InstallDir "appsettings.json"
    if (-not (Test-Path $settings)) { return "" }
    try {
        $json = Get-Content -Path $settings -Raw | ConvertFrom-Json
        if ($json.ServerUrl) { return ([string]$json.ServerUrl).TrimEnd("/") }
        if ($json.Agent -and $json.Agent.ServerUrl) { return ([string]$json.Agent.ServerUrl).TrimEnd("/") }
    } catch {}
    return ""
}

function Get-NeoFileHash {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return "" }
    try { return (Get-FileHash -Path $Path -Algorithm SHA256).Hash } catch { return "" }
}

function Test-AgentPackageCurrent {
    param([string]$InstallDir)
    $pairs = @(
        @((Join-Path $AgentDir "NeoOptimize.Agent.exe"), (Join-Path $InstallDir "NeoOptimize.Agent.exe")),
        @((Join-Path $AgentDir "signing.pub.pem"), (Join-Path $InstallDir "signing.pub.pem"))
    )
    foreach ($pair in $pairs) {
        $source = [string]$pair[0]
        $target = [string]$pair[1]
        if (-not (Test-Path $source)) { continue }
        $sourceHash = Get-NeoFileHash $source
        $targetHash = Get-NeoFileHash $target
        if ([string]::IsNullOrWhiteSpace($targetHash) -or $sourceHash -ne $targetHash) {
            Write-BootstrapLog "Agent package drift detected: $target"
            return $false
        }
    }
    return $true
}

Write-BootstrapLog "Bootstrap path: $PSCommandPath"
Write-BootstrapLog "Bootstrap elevated: $(Test-BootstrapAdministrator)"
if (-not (Test-BootstrapAdministrator)) {
    Start-ElevatedBootstrap
}

$cfg = Read-RmmConfig
if (-not $cfg.auto_install_agent) {
    Write-BootstrapLog "Auto-install disabled."
    exit 0
}

$selectedUrl = $null
foreach ($url in @($cfg.candidate_server_urls)) {
    Write-BootstrapLog "Checking RMM URL: $url"
    if (Test-RmmUrl $url) {
        $selectedUrl = [string]$url
        break
    }
}

if (-not $selectedUrl) {
    Write-BootstrapLog "No reachable RMM server found. Agent install skipped."
    exit 0
}

if (-not (Test-Path $Installer)) {
    Write-BootstrapLog "Bundled agent installer missing: $Installer"
    exit 1
}

$svcName = if ($cfg.service_name) { [string]$cfg.service_name } else { "NeoOptimize RMM Agent" }
$installDir = if ($cfg.agent_install_dir) { Expand-NeoPath ([string]$cfg.agent_install_dir) } else { Join-Path $env:ProgramFiles "NeoOptimize\Agent" }
$svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    $installedUrl = Get-InstalledAgentServerUrl -InstallDir $installDir
    if ($installedUrl -eq $selectedUrl.TrimEnd("/") -and (Test-AgentPackageCurrent -InstallDir $installDir)) {
        Write-BootstrapLog "RMM service already running and connected to $installedUrl"
        exit 0
    }
    Write-BootstrapLog "RMM service needs refresh. Installed URL='$installedUrl', selected URL='$selectedUrl'."
}

$collectDeviceCapabilities = if ($cfg.telemetry.PSObject.Properties.Name -contains "collect_device_capabilities") { [bool]$cfg.telemetry.collect_device_capabilities } else { $true }
$collectApproxLocation = [bool]$cfg.telemetry.collect_approx_location
$collectVerboseDiagnostics = [bool]$cfg.telemetry.collect_verbose_diagnostics
$token = [string]$cfg.enrollment_token
if ([string]::IsNullOrWhiteSpace($token)) {
    $token = $env:NEO_RMM_ENROLLMENT_TOKEN
    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = $env:AGENT_ENROLLMENT_TOKEN
    }
}

$agentInstallLog = Join-Path $LogDir "AgentInstall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

Write-BootstrapLog "Installing RMM agent. Server: $selectedUrl"
Write-BootstrapLog "Agent installer output: $agentInstallLog"

$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Stop"
$exitCode = 0
try {
    $agentOutput = & $Installer `
        -InstallDir $installDir `
        -ServerUrl $selectedUrl `
        -EnrollmentToken $token `
        -CollectDeviceCapabilities:$collectDeviceCapabilities `
        -CollectApproxLocation:$collectApproxLocation `
        -CollectVerboseDiagnostics:$collectVerboseDiagnostics 2>&1

    if ($agentOutput) {
        $agentOutput | Out-String | Out-File -FilePath $agentInstallLog -Encoding UTF8 -Append
    }
} catch {
    $exitCode = 1
    $failure = $_ | Out-String
    $failure | Out-File -FilePath $agentInstallLog -Encoding UTF8 -Append
    Write-BootstrapLog "Agent installer failed: $($_.Exception.Message)"
} finally {
    $ErrorActionPreference = $oldErrorActionPreference
}

Write-BootstrapLog "Installer exit code: $exitCode"
exit $exitCode
