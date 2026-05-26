#Requires -RunAsAdministrator
<# MODULE 20 - WINDOWS COMPONENT STORE CLEANUP #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "20" "DISM" "COMPONENT STORE CLEANUP"

$winSxs = Join-Path $env:WINDIR "WinSxS"
$size = Get-FolderSizeMB $winSxs
Write-Step "WINSXS INVENTORY"
Write-Host ""
Write-Info "WinSxS size estimate: $size MB"

Write-Host ""
Write-Step "DISM ANALYZE COMPONENT STORE"
Write-Host ""
$analysis = & dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1
$analysis | ForEach-Object { Write-Host "  $_" }

$dir = Join-Path $Global:LogDir "maintenance"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$reportPath = Join-Path $dir ("component-store_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$analysis | Set-Content -Path $reportPath -Encoding UTF8
Write-OK "Component store report: $reportPath"

if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) {
    Write-Warn "Non-interactive mode: audit only."
    Wait-AnyKey
    return
}

Write-Host ""
Write-Host "  [1] Audit only"
Write-Host "  [2] Run StartComponentCleanup"
Write-Host ""
$choice = Read-NeoChoice "  Pilihan [1-2]" @("1","2") "1"
if ($choice -eq "2" -and (Confirm-NeoAction "Run DISM StartComponentCleanup now?" $false)) {
    & dism.exe /Online /Cleanup-Image /StartComponentCleanup
    Write-OK "DISM StartComponentCleanup completed or queued by Windows."
}

Write-Host ""
Write-Separator "=" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)COMPONENT CLEANUP SELESAI$($Global:RESET)"
Write-Footer
Wait-AnyKey
