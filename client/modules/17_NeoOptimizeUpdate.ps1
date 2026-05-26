param(
    [string]$ArgsJson = "{}"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Get-ArgValue {
    param($Args, [string[]]$Names, [string]$Default = "")
    foreach ($name in $Names) {
        if ($Args.PSObject.Properties.Name -contains $name -and -not [string]::IsNullOrWhiteSpace([string]$Args.$name)) {
            return [string]$Args.$name
        }
    }
    return $Default
}

function Quote-PsLiteral {
    param([string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

$argsObj = $ArgsJson | ConvertFrom-Json
$installerUrl = Get-ArgValue $argsObj @("installer_url", "url", "download_url")
$packageSha256 = (Get-ArgValue $argsObj @("package_sha256", "sha256")).ToUpperInvariant()
$installerSha256 = (Get-ArgValue $argsObj @("installer_sha256")).ToUpperInvariant()
$silentArgs = Get-ArgValue $argsObj @("silent_args") "/S"
$updateToken = Get-ArgValue $argsObj @("update_token", "download_token")

if ([string]::IsNullOrWhiteSpace($installerUrl)) {
    throw "NEOUPDATE requires installer_url."
}
if ([string]::IsNullOrWhiteSpace($packageSha256) -and [string]::IsNullOrWhiteSpace($installerSha256)) {
    throw "NEOUPDATE requires SHA-256 package or installer hash."
}

$installerUri = [Uri]$installerUrl
if ($installerUri.Scheme -notin @("http", "https")) {
    throw "NEOUPDATE only allows http/https installer URLs."
}
if ($installerUri.Scheme -eq "http" -and $installerUri.Host -notin @("127.0.0.1", "localhost", "192.168.122.1")) {
    throw "NEOUPDATE requires HTTPS for non-lab update URLs."
}
if ($silentArgs -notmatch '^[A-Za-z0-9\s/:\-_.=]+$') {
    throw "NEOUPDATE silent_args contains unsupported characters."
}

$root = Join-Path $env:ProgramData "NeoOptimize\updates"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$work = Join-Path $root $stamp
New-Item -Path $work -ItemType Directory -Force | Out-Null

$downloadName = Split-Path ([Uri]$installerUrl).AbsolutePath -Leaf
if ([string]::IsNullOrWhiteSpace($downloadName)) { $downloadName = "NeoOptimize.exe" }
if ($downloadName -notmatch '^[A-Za-z0-9._-]+\.(exe|zip)$') { throw "Unsupported update package file name." }
$downloadPath = Join-Path $work $downloadName

$headers = @{}
if (-not [string]::IsNullOrWhiteSpace($updateToken)) {
    $headers["Authorization"] = "Bearer $updateToken"
}

Invoke-WebRequest -Uri $installerUrl -OutFile $downloadPath -UseBasicParsing -Headers $headers -TimeoutSec 120

if (-not [string]::IsNullOrWhiteSpace($packageSha256)) {
    $actualPackageHash = (Get-FileHash -Path $downloadPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualPackageHash -ne $packageSha256) {
        throw "Downloaded package hash mismatch. Expected $packageSha256, got $actualPackageHash."
    }
}

$installerPath = $downloadPath
if ($downloadPath.ToLowerInvariant().EndsWith(".zip")) {
    $extractDir = Join-Path $work "extract"
    New-Item -Path $extractDir -ItemType Directory -Force | Out-Null
    Expand-Archive -Path $downloadPath -DestinationPath $extractDir -Force
    $installer = Get-ChildItem -Path $extractDir -Filter "NeoOptimize.exe" -Recurse | Select-Object -First 1
    if (-not $installer) { throw "NeoOptimize.exe not found inside update package." }
    $installerPath = $installer.FullName
}

if (-not [string]::IsNullOrWhiteSpace($installerSha256)) {
    $actualInstallerHash = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualInstallerHash -ne $installerSha256) {
        throw "Installer hash mismatch. Expected $installerSha256, got $actualInstallerHash."
    }
}

$runnerPath = Join-Path $work "NeoOptimize_UpdateRunner.ps1"
$logPath = Join-Path $root "NeoOptimize_Update_$stamp.log"
$runner = @"
`$ErrorActionPreference = "Stop"
Start-Sleep -Seconds 3
Start-Transcript -Path $(Quote-PsLiteral $logPath) -Append -Force | Out-Null
try {
    Start-Process -FilePath $(Quote-PsLiteral $installerPath) -ArgumentList $(Quote-PsLiteral $silentArgs) -Wait -WindowStyle Hidden
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
"@
Set-Content -Path $runnerPath -Value $runner -Encoding UTF8

Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$runnerPath`"" -WindowStyle Hidden

[PSCustomObject]@{
    queued = $true
    installer_url = $installerUrl
    installer_path = $installerPath
    runner = $runnerPath
    log = $logPath
} | ConvertTo-Json -Compress
