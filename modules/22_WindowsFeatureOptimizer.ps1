#Requires -RunAsAdministrator
<# Wrapper: release source lives in client\modules\22_WindowsFeatureOptimizer.ps1 #>
$target = Join-Path (Split-Path -Parent $PSScriptRoot) "client\modules\22_WindowsFeatureOptimizer.ps1"
if (Test-Path $target) { . $target } else { Write-Host "Missing $target" -ForegroundColor Yellow }
