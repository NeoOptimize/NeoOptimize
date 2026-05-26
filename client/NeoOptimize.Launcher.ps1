#Requires -Version 5.1
<#
.SYNOPSIS
    Windowless launcher for NeoOptimize.

.DESCRIPTION
    Starts the NeoOptimize WPF UI without depending on Windows Script Host.
    If administrator rights are missing, it relaunches itself through UAC.
#>

param(
    [switch]$Console,
    [switch]$UpdateManager,
    [switch]$Tray,
    [switch]$OpenChat
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$logDir = Join-Path $env:ProgramData "NeoOptimize\logs"
$logPath = Join-Path $logDir "NeoOptimizeLauncher.log"

function Write-NeoLauncherLog {
    param([string]$Message)
    try {
        if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
        Add-Content -Path $logPath -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
    } catch {}
}

function Test-NeoAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-NeoPowerShell {
    $ps = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $ps) { return $ps }
    return "powershell.exe"
}

function Test-NeoTrayRunning {
    try {
        $matches = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" |
            Where-Object { $_.CommandLine -match "NeoOptimize\.Tray\.ps1" }
        return (@($matches).Count -gt 0)
    } catch {
        return $false
    }
}

function Start-NeoTrayCompanion {
    if ($env:NEOOPTIMIZE_DISABLE_TRAY -eq "1") { return }
    $target = Join-Path $root "NeoOptimize.Tray.ps1"
    if (-not (Test-Path $target)) {
        Write-NeoLauncherLog "Tray companion missing: $target"
        return
    }
    if (Test-NeoTrayRunning) {
        Write-NeoLauncherLog "Tray companion already running."
        return
    }
    $ps = Get-NeoPowerShell
    $args = "-Sta -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$target`""
    Start-Process -FilePath $ps -ArgumentList $args -WorkingDirectory $root -WindowStyle Hidden | Out-Null
    Write-NeoLauncherLog "Started tray companion."
}

try {
    $ps = Get-NeoPowerShell
    $self = $PSCommandPath

    if ((-not (Test-NeoAdmin)) -and (-not $Tray)) {
        $args = @("-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", "`"$self`"")
        if ($Console) { $args += "-Console" }
        if ($UpdateManager) { $args += "-UpdateManager" }
        Start-Process -FilePath $ps -ArgumentList ($args -join " ") -WorkingDirectory $root -Verb RunAs -WindowStyle Hidden
        Write-NeoLauncherLog "Requested elevated launcher."
        exit 0
    }

    if ($Console) {
        $target = Join-Path $root "NeoOptimize.ps1"
        $args = "-NoProfile -ExecutionPolicy Bypass -File `"$target`""
        Start-Process -FilePath $ps -ArgumentList $args -WorkingDirectory $root -WindowStyle Normal
        Write-NeoLauncherLog "Started console mode."
        exit 0
    }

    if ($UpdateManager) {
        $target = Join-Path $root "NeoOptimize.UpdateManager.ps1"
        $args = "-NoProfile -ExecutionPolicy Bypass -File `"$target`" -Mode Check"
        Start-Process -FilePath $ps -ArgumentList $args -WorkingDirectory $root -WindowStyle Hidden
        Write-NeoLauncherLog "Started update manager check."
        exit 0
    }

    if ($Tray) {
        $target = Join-Path $root "NeoOptimize.Tray.ps1"
        $args = "-Sta -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$target`""
        if ($OpenChat) { $args = "$args -OpenChat" }
        Start-Process -FilePath $ps -ArgumentList $args -WorkingDirectory $root -WindowStyle Hidden
        Write-NeoLauncherLog "Started tray companion."
        exit 0
    }

    $ui = Join-Path $root "NeoOptimize.UI.ps1"
    if (-not (Test-Path $ui)) {
        throw "NeoOptimize.UI.ps1 was not found in $root"
    }

    Start-NeoTrayCompanion
    $uiArgs = "-Sta -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ui`""
    Start-Process -FilePath $ps -ArgumentList $uiArgs -WorkingDirectory $root -WindowStyle Hidden
    Write-NeoLauncherLog "Started NeoOptimize UI."
} catch {
    Write-NeoLauncherLog ("Launcher error: {0}" -f $_.Exception.Message)
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
    [System.Windows.MessageBox]::Show(
        "NeoOptimize could not start.`n`n$($_.Exception.Message)`n`nLog: $logPath",
        "NeoOptimize",
        "OK",
        "Error"
    ) | Out-Null
    exit 1
}
