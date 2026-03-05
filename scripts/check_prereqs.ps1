<#
Check prerequisites for building and running NeoOptimize on Windows.
Outputs guidance and returns non-zero exit code when critical items are missing.
#>
param()

function Write-Ok($msg){ Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn($msg){ Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg){ Write-Host "[ERR]   $msg" -ForegroundColor Red }

$errors = @()

# Ensure running on Windows
if ($env:OS -notlike '*Windows*'){
    Write-Err "This script is intended to run on Windows."
    exit 2
} else { Write-Ok "Running on Windows." }

# Check dotnet
try {
    $dotnet = & dotnet --info 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $dotnet) { throw 'dotnet not found' }
    Write-Ok "dotnet detected"
    $sdks = & dotnet --list-sdks 2>$null
    Write-Host $sdks
    if ($sdks -match '^8\.') { Write-Ok "Found .NET 8 SDK." } else { Write-Warn "No .NET 8 SDK found. Project targets net8.0; please install .NET 8 SDK."; $errors += 'dotnet8' }
} catch {
    Write-Err "dotnet CLI not found. Install .NET SDK from https://aka.ms/dotnet-download"
    $errors += 'dotnet' 
}

# Check msbuild / Visual Studio build tools
$msb = Get-Command msbuild -ErrorAction SilentlyContinue
if ($msb) { Write-Ok "msbuild found: $($msb.Source)" } else {
    # try to locate MSBuild.exe in common VS paths
    $msbuildPaths = @(
        "$Env:ProgramFiles(x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "$Env:ProgramFiles(x86)\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "$Env:ProgramFiles(x86)\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
    )
    $found = $false
    foreach ($p in $msbuildPaths){ if (Test-Path $p){ Write-Ok "msbuild found: $p"; $found = $true; break } }
    if (-not $found){ Write-Warn "msbuild not found. Install Visual Studio Build Tools or Developer Command Prompt."; $errors += 'msbuild' }
}

# Check MSVC C++ compiler (optional but required for native engine)
$cl = Get-Command cl.exe -ErrorAction SilentlyContinue
if ($cl) { Write-Ok "MSVC (cl.exe) found: $($cl.Source)" } else { Write-Warn "MSVC compiler (cl.exe) not found. Install C++ build tools if you plan to build native engine." }

# Check Windows App SDK (informational)
Write-Host "Checking for Windows App SDK (informational)..."
try{
    $regKey = 'HKLM:\SOFTWARE\Microsoft\WindowsAppRuntime'
    if (Test-Path $regKey){ $v = Get-ItemProperty -Path $regKey -ErrorAction SilentlyContinue; Write-Ok "Windows App Runtime registry key present." } else { Write-Warn "Windows App Runtime registry key not found. Install Windows App SDK (e.g. 1.4.x) for WinUI projects." }
} catch { Write-Warn "Unable to inspect registry for Windows App Runtime." }

# Summary
if ($errors.Count -gt 0){
    Write-Err "Critical prerequisites missing: $($errors -join ', ')"
    Write-Host "See INSTALL.md in repository root for install instructions."
    exit 3
} else {
    Write-Ok "All critical prerequisites detected (dotnet 8 + msbuild). Non-critical items may still be missing."; exit 0
}
