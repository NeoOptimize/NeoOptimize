<#
Build script for NeoOptimize.Engine (x64) and copy DLL to .NET app outputs.
Usage: Run in PowerShell (Developer Command Prompt not required if MSBuild on PATH).
#>

$proj = "D:\\NeoOptimize\\NeoOptimize.Engine\\NeoOptimize.Engine.vcxproj"
$config = "Release"
$platform = "x64"

Write-Host "Building NeoOptimize.Engine ($config|$platform)..."

function Find-MSBuild {
    $ms = Get-Command msbuild -ErrorAction SilentlyContinue
    if ($ms) { return $ms.Source }
    $vswhere = "$Env:ProgramFiles(x86)\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { $vswhere = "$Env:ProgramFiles\Microsoft Visual Studio\Installer\vswhere.exe" }
    if (Test-Path $vswhere) {
        $inst = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath 2>$null
        if ($inst) {
            $msbuild = Join-Path $inst "MSBuild\Current\Bin\MSBuild.exe"
            if (Test-Path $msbuild) { return $msbuild }
            $msbuild = Join-Path $inst "MSBuild\15.0\Bin\MSBuild.exe"
            if (Test-Path $msbuild) { return $msbuild }
        }
    }
    $candidates = @(
        "$Env:ProgramFiles(x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "$Env:ProgramFiles(x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe",
        "$Env:ProgramFiles(x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "$Env:ProgramFiles(x86)\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return $null
}

# Also check for Build Tools installed to C:\BuildTools (common when using vs_BuildTools installer)
function Find-MSBuild-Extended {
    $m = Find-MSBuild
    if ($m) { return $m }
    $c = 'C:\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
    if (Test-Path $c) { return $c }
    return $null
}

$msbuild = Find-MSBuild-Extended
if (-not $msbuild) { Write-Error "MSBuild not found. Install Visual Studio Build Tools or run script from Developer Command Prompt."; exit 1 }

Write-Host "Using MSBuild: $msbuild"
# Pass arguments as an array to avoid quoting issues
$msbuildArgs = @(
    $proj,
    "/p:Configuration=$config",
    "/p:Platform=$platform",
    "/t:Build",
    "/m"
)
$rc = & $msbuild @msbuildArgs
if ($LASTEXITCODE -ne 0) { Write-Error "msbuild failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }


# Determine produced DLL path under project folder (common MSBuild output)
$projDir = Split-Path $proj -Parent
$dllPath = Join-Path $projDir "bin\$config\NeoOptimize.Engine.dll"
if (-not (Test-Path $dllPath)) {
    $alt = Join-Path $projDir "bin\$config\x64\NeoOptimize.Engine.dll"
    if (Test-Path $alt) { $dllPath = $alt }
}

if (-not (Test-Path $dllPath)) {
    # Try older layout or project-specific outdir
    $candidate = Join-Path $projDir "..\bin\$config\NeoOptimize.Engine.dll"
    if (Test-Path $candidate) { $dllPath = $candidate }
}

if (-not (Test-Path $dllPath)) { Write-Warning "DLL not found after build. Locate NeoOptimize.Engine.dll and copy it to outputs manually."; exit 1 }

Write-Host "Copying DLL to .NET app outputs..."
$dotnetUi = "D:\\NeoOptimize\\NeoOptimize.UI\\bin\\$config\\net8.0-windows10.0.19041.0\\win10-x64\\"
$console = "D:\\NeoOptimize\\NeoOptimize.UI.ConsoleTest\\bin\\$config\\net8.0\\"
foreach ($dest in @($dotnetUi, $console)) {
    if (-not (Test-Path $dest)) { New-Item -Path $dest -ItemType Directory -Force | Out-Null }
    Copy-Item $dllPath -Destination (Join-Path $dest "NeoOptimize.Engine.dll") -Force
}

Write-Host "Build and copy complete. DLL placed into app output folders."
