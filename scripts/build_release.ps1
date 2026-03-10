param(
    [string]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Script,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    Write-Host $Description
    & $Script
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE"
    }
}

function Update-PortableConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [Parameter(Mandatory = $true)]
        [string]$RegistrationStatePath,
        [string]$ReportsRootPath
    )

    $json = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
    $json.NeoOptimize.RegistrationStatePath = $RegistrationStatePath
    if ($ReportsRootPath) {
        if ($null -eq $json.NeoOptimize.PSObject.Properties['ReportsRootPath']) {
            $json.NeoOptimize | Add-Member -NotePropertyName ReportsRootPath -NotePropertyValue $ReportsRootPath
        } else {
            $json.NeoOptimize.ReportsRootPath = $ReportsRootPath
        }
    }

    $json | ConvertTo-Json -Depth 8 | Set-Content -Path $ConfigPath
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$timestamp = Get-Date -Format 'yyyyMMddHHmmss'
$publishRoot = Join-Path $repoRoot 'artifacts\publish'
$installerRoot = Join-Path $repoRoot 'artifacts\installer'
$templatePath = Join-Path $repoRoot 'installer\wix\NeoOptimize.Installer.wxs'
$resourceRoot = Join-Path $repoRoot 'installer\resources'

$architectures = @(
    @{
        Name = 'x64'
        Runtime = 'win-x64'
        WixArch = 'x64'
        ProgramFilesId = 'ProgramFiles64Folder'
        UpgradeCode = '7E3D6D3D-6F4F-4A52-9D44-50A15AF87F8E'
    },
    @{
        Name = 'x86'
        Runtime = 'win-x86'
        WixArch = 'x86'
        ProgramFilesId = 'ProgramFilesFolder'
        UpgradeCode = '0E07F777-1A89-4CA7-8AFB-314C8C55AFB1'
    }
)

foreach ($architecture in $architectures) {
    $archName = $architecture.Name
    $runtime = $architecture.Runtime
    $publishArchRoot = Join-Path $publishRoot $runtime
    $appPublish = Join-Path $publishArchRoot 'app'
    $servicePublish = Join-Path $publishArchRoot 'service'
    $releaseName = "NeoOptimize-v$Version-$runtime-$timestamp"
    $releaseRoot = Join-Path $repoRoot "dist\$releaseName"
    $zipPath = Join-Path $repoRoot "dist\$releaseName.zip"
    $msiPath = Join-Path $installerRoot "NeoOptimize-v$Version-$archName.msi"
    $wixSourcePath = Join-Path $installerRoot "NeoOptimize.$archName.wxs"

    Remove-Item -Recurse -Force $appPublish, $servicePublish, $releaseRoot -ErrorAction SilentlyContinue
    if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
    New-Item -ItemType Directory -Force -Path $appPublish, $servicePublish, $installerRoot, $releaseRoot | Out-Null

    Invoke-External -Description "Publishing NeoOptimize.App $Version for $runtime..." -Script {
        dotnet publish (Join-Path $repoRoot 'client_windows\NeoOptimize\src\NeoOptimize.App\NeoOptimize.App.csproj') `
          -c Release -r $runtime --self-contained true `
          /p:DebugType=None /p:DebugSymbols=false /p:UseSharedCompilation=false `
          -o $appPublish
    }

    Invoke-External -Description "Publishing NeoOptimize.Service $Version for $runtime..." -Script {
        dotnet publish (Join-Path $repoRoot 'client_windows\NeoOptimize\src\NeoOptimize.Service\NeoOptimize.Service.csproj') `
          -c Release -r $runtime --self-contained true `
          /p:DebugType=None /p:DebugSymbols=false /p:UseSharedCompilation=false `
          -o $servicePublish
    }

    $wixSource = Get-Content -Raw -Path $templatePath
    $wixSource = $wixSource.Replace('ProgramFiles64Folder', $architecture.ProgramFilesId)
    $wixSource = $wixSource.Replace('7E3D6D3D-6F4F-4A52-9D44-50A15AF87F8E', $architecture.UpgradeCode)
    Set-Content -Path $wixSourcePath -Value $wixSource

    Invoke-External -Description "Building MSI installer for $archName..." -Script {
        wix build $wixSourcePath `
          -arch $($architecture.WixArch) `
          -ext WixToolset.UI.wixext `
          -b resources=$resourceRoot `
          -b app=$appPublish `
          -b service=$servicePublish `
          -o $msiPath
    }

    Invoke-External -Description "Validating MSI installer for $archName..." -Script {
        wix msi validate $msiPath
    }

    $appRelease = Join-Path $releaseRoot 'App'
    $serviceRelease = Join-Path $releaseRoot 'Service'
    $installerRelease = Join-Path $releaseRoot 'Installer'
    $dataRelease = Join-Path $releaseRoot 'Data'
    $reportRelease = Join-Path $dataRelease 'reports'
    New-Item -ItemType Directory -Force -Path $appRelease, $serviceRelease, $installerRelease, $reportRelease | Out-Null

    Copy-Item -Recurse -Force (Join-Path $appPublish '*') $appRelease
    Copy-Item -Recurse -Force (Join-Path $servicePublish '*') $serviceRelease
    Copy-Item -Force $msiPath $installerRelease
    Copy-Item -Force (Join-Path $repoRoot 'LICENSE.txt') $releaseRoot

    Update-PortableConfig -ConfigPath (Join-Path $appRelease 'appsettings.json') -RegistrationStatePath '..\Data\registration.json' -ReportsRootPath '..\Data\reports'
    Update-PortableConfig -ConfigPath (Join-Path $serviceRelease 'appsettings.json') -RegistrationStatePath '..\Data\registration.json'

    Set-Content -Path (Join-Path $releaseRoot 'NeoOptimize-Portable.cmd') -Value @"
@echo off
setlocal
cd /d "%~dp0"
start "NeoOptimize Service" /min "%~dp0Service\NeoOptimize.Service.exe"
timeout /t 2 >nul
start "NeoOptimize App" "%~dp0App\NeoOptimize.App.exe"
endlocal
"@

    Set-Content -Path (Join-Path $releaseRoot 'Start-NeoOptimize-Service.cmd') -Value @"
@echo off
cd /d "%~dp0"
start "NeoOptimize Service" /min "%~dp0Service\NeoOptimize.Service.exe"
"@

    Set-Content -Path (Join-Path $releaseRoot 'Start-NeoOptimize-App.cmd') -Value @"
@echo off
cd /d "%~dp0"
start "NeoOptimize App" "%~dp0App\NeoOptimize.App.exe"
"@

    Set-Content -Path (Join-Path $releaseRoot 'INSTALL.txt') -Value @"
NeoOptimize $Version ($runtime)

Installer:
- Run Installer\$(Split-Path -Leaf $msiPath)
- Review and accept the NeoOptimize license agreement during setup.
- The installer deploys both the desktop app and the NeoOptimize background service.

Portable local usage:
- Use NeoOptimize-Portable.cmd to launch the local background service and app from this folder.
- Portable mode stores registration in Data\registration.json.
- Portable mode stores reports in Data\reports.
- This layout is suitable for external drive usage.
"@

    Compress-Archive -Path (Join-Path $releaseRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal

    Write-Host "Created $releaseRoot"
    Write-Host "Created $zipPath"
}


