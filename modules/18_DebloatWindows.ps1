#Requires -RunAsAdministrator
<# MODULE 18 - SELECTABLE WINDOWS DEBLOAT #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "18" "APP" "SELECTABLE WINDOWS DEBLOAT"
Write-Info "Modul debloat rilis utama ada di client\modules\09_Apps.ps1."
Write-Info "Menjalankan debloater selectable yang melindungi Camera, Photos, Store, Calculator, dan App Installer."

$clientDebloater = Join-Path (Split-Path -Parent $PSScriptRoot) "client\modules\09_Apps.ps1"
if (Test-Path $clientDebloater) {
    . $clientDebloater
} else {
    Write-Warn "client\modules\09_Apps.ps1 tidak ditemukan. Tidak ada perubahan diterapkan."
    Wait-AnyKey
}
