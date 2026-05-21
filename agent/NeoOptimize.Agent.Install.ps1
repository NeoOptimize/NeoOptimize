#Requires -RunAsAdministrator
param(
    [string]$InstallDir = "$env:ProgramFiles\NeoOptimize\Agent",
    [string]$ServerUrl = "",
    [string]$EnrollmentToken = "",
    [bool]$AllowInsecureTls = $false,
    [int]$TelemetryIntervalSeconds = 1,
    [bool]$CollectDeviceCapabilities = $true,
    [bool]$CollectApproxLocation = $false,
    [bool]$CollectVerboseDiagnostics = $false,
    [bool]$EnableLabCommands = $false,
    [bool]$EnableTamperProtection = $false
)

$ErrorActionPreference = "Stop"
$ServiceName = "NeoOptimize RMM Agent"
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExeSource = Join-Path $SourceDir "NeoOptimize.Agent.exe"
$ExeTarget = Join-Path $InstallDir "NeoOptimize.Agent.exe"

if (-not (Test-Path $ExeSource)) {
    throw "NeoOptimize.Agent.exe was not found next to this installer script."
}

Write-Host "[+] Installing NeoOptimize RMM Agent to $InstallDir"

$SourceConfig = Join-Path $SourceDir "appsettings.json"
$ExistingConfig = $null
if (Test-Path $SourceConfig) {
    try {
        $ExistingConfig = Get-Content -Raw -Path $SourceConfig | ConvertFrom-Json
    } catch {
        Write-Warning "Could not parse source appsettings.json; installer parameters will be used."
    }
}

if ([string]::IsNullOrWhiteSpace($ServerUrl)) {
    if ($ExistingConfig -and $ExistingConfig.ServerUrl) {
        $ServerUrl = [string]$ExistingConfig.ServerUrl
    } else {
        $ServerUrl = "http://localhost:3000"
    }
}

if ([string]::IsNullOrWhiteSpace($EnrollmentToken) -and $ExistingConfig -and $ExistingConfig.EnrollmentToken) {
    $EnrollmentToken = [string]$ExistingConfig.EnrollmentToken
}

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[+] Stopping existing service"
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 2
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path $ExeSource -Destination $ExeTarget -Force

foreach ($folder in @("modules", "lib")) {
    $src = Join-Path $SourceDir $folder
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $InstallDir -Recurse -Force
    }
}

foreach ($file in @("signing.pub.pem", "NeoOptimize_Uninstaller.ps1")) {
    $src = Join-Path $SourceDir $file
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination (Join-Path $InstallDir $file) -Force
    }
}

$config = [ordered]@{
    ServerUrl = $ServerUrl.TrimEnd("/")
    ApiKey = ""
    EnrollmentToken = $EnrollmentToken
    AllowInsecureTls = $AllowInsecureTls
    Telemetry = [ordered]@{
        IntervalSeconds = $TelemetryIntervalSeconds
        CollectDeviceCapabilities = $CollectDeviceCapabilities
        CollectApproxLocation = $CollectApproxLocation
        CollectVerboseDiagnostics = $CollectVerboseDiagnostics
    }
    Safety = [ordered]@{
        SecureStorePath = "%ProgramData%\NeoOptimize\SecureStore"
        CrashLoopThreshold = 2
        EnableLabCommands = $EnableLabCommands
        MaxMonitoringSeconds = 900
        RegistrySnapshotMaxDepth = 2
        RegistrySnapshotMaxKeys = 2500
        RegistrySnapshotMaxValues = 10000
    }
}
$config | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -Path (Join-Path $InstallDir "appsettings.json")

$binaryPath = "`"$ExeTarget`""
if ($EnableTamperProtection) {
    $binaryPath = "$binaryPath --enable-tamper-protection"
}

New-Service -Name $ServiceName `
    -BinaryPathName $binaryPath `
    -DisplayName "NeoOptimize RMM Agent" `
    -Description "Authorized NeoOptimize remote monitoring and maintenance agent." `
    -StartupType Automatic | Out-Null

Start-Service -Name $ServiceName
Get-Service -Name $ServiceName | Format-Table -AutoSize
Write-Host "[+] NeoOptimize RMM Agent installation complete."
