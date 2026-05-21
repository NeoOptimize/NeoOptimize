param(
    [string]$InstallDir = "$env:ProgramFiles\NeoOptimize\Agent",
    [string]$ServerUrl = "",
    [string]$EnrollmentToken = "",
    [bool]$AllowInsecureTls = $false,
    [bool]$CollectDeviceCapabilities = $true,
    [bool]$CollectApproxLocation = $false,
    [bool]$CollectVerboseDiagnostics = $false,
    [bool]$CollectCameraCapture = $false,
    [bool]$CollectMicrophoneCapture = $false,
    [bool]$CollectBiometricData = $false,
    [bool]$EnableTamperProtection = $false
)

$ErrorActionPreference = "Stop"
$ServiceName = "NeoOptimize RMM Agent"
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExeSource = Join-Path $SourceDir "NeoOptimize.Agent.exe"
$ExeTarget = Join-Path $InstallDir "NeoOptimize.Agent.exe"
$LogDir = Join-Path $env:ProgramData "NeoOptimize\logs"
try {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
} catch {
    $LogDir = Join-Path $env:TEMP "NeoOptimize\logs"
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$InstallLog = Join-Path $LogDir ("AgentInstall_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$TranscriptStarted = $false
try {
    Start-Transcript -Path $InstallLog -Append -Force | Out-Null
    $TranscriptStarted = $true
    Write-Host "[+] Agent install log: $InstallLog"
} catch {
    Write-Warning "Could not start install transcript: $($_.Exception.Message)"
}

trap {
    if ($TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch {}
    }
    throw
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Administrator privileges are required to install the NeoOptimize RMM Agent service."
}

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

if ($ExistingConfig -and $ExistingConfig.Telemetry) {
    if ($ExistingConfig.Telemetry.PSObject.Properties.Name -contains "CollectCameraCapture") {
        $CollectCameraCapture = [bool]$ExistingConfig.Telemetry.CollectCameraCapture
    }
    if ($ExistingConfig.Telemetry.PSObject.Properties.Name -contains "CollectMicrophoneCapture") {
        $CollectMicrophoneCapture = [bool]$ExistingConfig.Telemetry.CollectMicrophoneCapture
    }
    if ($ExistingConfig.Telemetry.PSObject.Properties.Name -contains "CollectBiometricData") {
        $CollectBiometricData = [bool]$ExistingConfig.Telemetry.CollectBiometricData
    }
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
        CollectDeviceCapabilities = $CollectDeviceCapabilities
        CollectApproxLocation = $CollectApproxLocation
        CollectVerboseDiagnostics = $CollectVerboseDiagnostics
        CollectCameraCapture = $CollectCameraCapture
        CollectMicrophoneCapture = $CollectMicrophoneCapture
        CollectBiometricData = $CollectBiometricData
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
if ($TranscriptStarted) {
    try { Stop-Transcript | Out-Null } catch {}
}
return
