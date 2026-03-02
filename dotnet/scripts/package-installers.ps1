param(
  [ValidateSet("core-only", "core+ai", "both")]
  [string]$Variant = "both",
  [string]$ProductVersion = "1.0.0",
  [string]$Configuration = "Release",
  [string]$Runtime = "win-x64",
  [string]$AiRuntimeSource = "",
  [switch]$SelfContained
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Require-Command {
  param([Parameter(Mandatory = $true)][string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' was not found in PATH."
  }
}

function Reset-Directory {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (Test-Path $Path) {
    Remove-Item -Recurse -Force $Path
  }
  New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Invoke-WixBuild {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][int]$IncludeAi,
    [Parameter(Mandatory = $true)][string]$WxsPath,
    [Parameter(Mandatory = $true)][string]$PublishPath,
    [Parameter(Mandatory = $true)][string]$AiPath,
    [Parameter(Mandatory = $true)][string]$OutPath,
    [Parameter(Mandatory = $true)][string]$Version
  )

  $msiPath = Join-Path $OutPath "NeoOptimize-$Name.msi"
  $args = @(
    "build",
    $WxsPath,
    "-d", "ProductVersion=$Version",
    "-d", "CoreSourceDir=$PublishPath",
    "-d", "AiSourceDir=$AiPath",
    "-d", "IncludeAi=$IncludeAi",
    "-o", $msiPath
  )

  Write-Host "Building installer: $msiPath"
  & wix @args
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dotnetRoot = Split-Path -Parent $scriptDir

$solutionPath = Join-Path $dotnetRoot "NeoOptimize.slnx"
$appProjectPath = Join-Path $dotnetRoot "NeoOptimize.App\NeoOptimize.App.csproj"
$installerConfigPath = Join-Path $dotnetRoot "NeoOptimize.Installer\InstallerConfig.wxs"
$publishDir = Join-Path $dotnetRoot "out\publish"
$installersDir = Join-Path $dotnetRoot "out\installers"
$aiRuntimeDir = Join-Path $dotnetRoot "runtime\ai"

Require-Command -Name "dotnet"
Require-Command -Name "wix"

Reset-Directory -Path $publishDir
Reset-Directory -Path $installersDir
New-Item -ItemType Directory -Path $aiRuntimeDir -Force | Out-Null

if (-not [string]::IsNullOrWhiteSpace($AiRuntimeSource)) {
  if (-not (Test-Path $AiRuntimeSource)) {
    throw "AiRuntimeSource path not found: $AiRuntimeSource"
  }

  Write-Host "Syncing AI runtime from: $AiRuntimeSource"
  Get-ChildItem -Path $aiRuntimeDir -Force | Remove-Item -Recurse -Force
  Copy-Item -Path (Join-Path $AiRuntimeSource "*") -Destination $aiRuntimeDir -Recurse -Force
}

$selfContainedText = if ($SelfContained.IsPresent) { "true" } else { "false" }
Write-Host "Publishing app to: $publishDir"
dotnet publish $appProjectPath -c $Configuration -r $Runtime --self-contained $selfContainedText -o $publishDir

$hasAiFiles = (Get-ChildItem -Path $aiRuntimeDir -File -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
if (-not $hasAiFiles) {
  Set-Content -Path (Join-Path $aiRuntimeDir "README.txt") -Value "Place offline AI runtime/model files in this folder for Core+AI installer." -Encoding UTF8
}

switch ($Variant) {
  "core-only" {
    Invoke-WixBuild -Name "CoreOnly" -IncludeAi 0 -WxsPath $installerConfigPath -PublishPath $publishDir -AiPath $aiRuntimeDir -OutPath $installersDir -Version $ProductVersion
  }
  "core+ai" {
    Invoke-WixBuild -Name "CorePlusAI" -IncludeAi 1 -WxsPath $installerConfigPath -PublishPath $publishDir -AiPath $aiRuntimeDir -OutPath $installersDir -Version $ProductVersion
  }
  "both" {
    Invoke-WixBuild -Name "CoreOnly" -IncludeAi 0 -WxsPath $installerConfigPath -PublishPath $publishDir -AiPath $aiRuntimeDir -OutPath $installersDir -Version $ProductVersion
    Invoke-WixBuild -Name "CorePlusAI" -IncludeAi 1 -WxsPath $installerConfigPath -PublishPath $publishDir -AiPath $aiRuntimeDir -OutPath $installersDir -Version $ProductVersion
  }
}

Write-Host "Installer outputs:"
Get-ChildItem -Path $installersDir -Filter "*.msi" | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
