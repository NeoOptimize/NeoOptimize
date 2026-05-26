#Requires -RunAsAdministrator
<# Wrapper: release source lives in client\modules\29_ZeroTrustSecurity.ps1 #>
$target = Join-Path (Split-Path -Parent $PSScriptRoot) "client\modules\29_ZeroTrustSecurity.ps1"
if (Test-Path $target) { . $target } else { Write-Host "Missing source module: $target" -ForegroundColor Red }
