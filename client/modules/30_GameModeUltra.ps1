#Requires -RunAsAdministrator
<# MODULE 30 - GAME MODE ULTRA #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "30" "GAME" "GAME MODE ULTRA"

function Get-NeoRegValue {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

$gameBarPath = "HKCU:\Software\Microsoft\GameBar"
$gameConfigPath = "HKCU:\System\GameConfigStore"
$gameDvrPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
$graphicsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"

$report = [PSCustomObject]@{
    captured_at = (Get-Date).ToString("o")
    game_mode_auto = Get-NeoRegValue $gameBarPath "AutoGameModeEnabled"
    game_mode_allowed = Get-NeoRegValue $gameBarPath "AllowAutoGameMode"
    game_dvr_enabled = Get-NeoRegValue $gameConfigPath "GameDVR_Enabled"
    game_dvr_policy = Get-NeoRegValue $gameDvrPolicyPath "AllowGameDVR"
    hags_hwschmode = Get-NeoRegValue $graphicsPath "HwSchMode"
    active_power_scheme = (& powercfg.exe /getactivescheme 2>&1)
    timer_policy = (& bcdedit.exe /enum 2>&1 | Select-String -Pattern "useplatformclock|disabledynamictick|tscsyncpolicy")
    gpu = @(Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, VideoProcessor)
}

Write-Step "GAMING POSTURE"
Write-Host ""
Write-Info ("Auto Game Mode     : {0}" -f $(if ($null -eq $report.game_mode_auto) { "not configured" } else { $report.game_mode_auto }))
Write-Info ("GameDVR user state : {0}" -f $(if ($null -eq $report.game_dvr_enabled) { "not configured" } else { $report.game_dvr_enabled }))
Write-Info ("GameDVR policy     : {0}" -f $(if ($null -eq $report.game_dvr_policy) { "not configured" } else { $report.game_dvr_policy }))
Write-Info ("HAGS HwSchMode     : {0}" -f $(if ($null -eq $report.hags_hwschmode) { "not configured" } else { $report.hags_hwschmode }))
Write-Info ("Power scheme       : {0}" -f (($report.active_power_scheme | Out-String).Trim()))
if ($report.timer_policy) {
    Write-Warn "BCDEdit timer overrides detected. NeoOptimize will not change BCDEdit automatically."
}

$dir = Join-Path $Global:LogDir "gaming"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$path = Join-Path $dir ("game-mode-ultra_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$report | ConvertTo-Json -Depth 7 | Set-Content -Path $path -Encoding UTF8
Write-OK "Game Mode report: $path"

if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) {
    Write-Warn "Non-interactive mode: audit only."
    Wait-AnyKey
    return
}

Write-Host ""
Write-Host "  [1] Audit only"
Write-Host "  [2] Apply safe gaming profile (Game Mode on, GameDVR capture off)"
Write-Host "  [3] Enable HAGS policy when supported (reboot required)"
Write-Host ""
$choice = Read-NeoChoice "  Pilihan [1-3]" @("1","2","3") "1"

if ($choice -eq "2" -and (Confirm-NeoAction "Apply safe gaming profile?" $false)) {
    Backup-RegKey $gameBarPath | Out-Null
    Backup-RegKey $gameConfigPath | Out-Null
    Backup-RegKey $gameDvrPolicyPath | Out-Null
    Set-Reg $gameBarPath "AllowAutoGameMode" 1
    Set-Reg $gameBarPath "AutoGameModeEnabled" 1
    Set-Reg $gameConfigPath "GameDVR_Enabled" 0
    Set-Reg $gameDvrPolicyPath "AllowGameDVR" 0
    Write-OK "Safe gaming profile applied. No BCDEdit or HPET changes were made."
}

if ($choice -eq "3" -and (Confirm-NeoAction "Enable HAGS policy? Reboot required and unsupported drivers may ignore it." $false)) {
    Backup-RegKey $graphicsPath | Out-Null
    Set-Reg $graphicsPath "HwSchMode" 2
    Write-OK "HAGS policy set. Reboot Windows and verify in Graphics Settings."
}

Write-Footer
Wait-AnyKey
