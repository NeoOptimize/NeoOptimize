#Requires -RunAsAdministrator
<# Wrapper: release source lives in client\modules\20_ComponentCleanup.ps1 #>
$target = Join-Path (Split-Path -Parent $PSScriptRoot) "client\modules\20_ComponentCleanup.ps1"
if (Test-Path $target) { . $target } else { Write-Host "Missing $target" -ForegroundColor Yellow }
