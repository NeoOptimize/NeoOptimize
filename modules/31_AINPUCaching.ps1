#Requires -RunAsAdministrator
<# Wrapper: release source lives in client\modules\31_AINPUCaching.ps1 #>
$target = Join-Path (Split-Path -Parent $PSScriptRoot) "client\modules\31_AINPUCaching.ps1"
if (Test-Path $target) { . $target } else { Write-Host "Missing source module: $target" -ForegroundColor Red }
