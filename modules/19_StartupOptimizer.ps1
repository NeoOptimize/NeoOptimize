#Requires -RunAsAdministrator
<# Wrapper: release source lives in client\modules\19_StartupOptimizer.ps1 #>
$target = Join-Path (Split-Path -Parent $PSScriptRoot) "client\modules\19_StartupOptimizer.ps1"
if (Test-Path $target) { . $target } else { Write-Host "Missing $target" -ForegroundColor Yellow }
