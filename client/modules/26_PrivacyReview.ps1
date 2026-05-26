#Requires -RunAsAdministrator
<# MODULE 26 - PRIVACY REVIEW #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "26" "PRV" "PRIVACY REVIEW"

function Get-NeoRegValue {
    param([string]$Path, [string]$Name)
    try {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    } catch {
        return $null
    }
}

$appPrivacyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
$locationPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
$dataPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
$capPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore"

$sensitivePolicies = @(
    [PSCustomObject]@{ Area="Camera"; OrgPolicy=Get-NeoRegValue $appPrivacyPath "LetAppsAccessCamera"; UserValue=Get-NeoRegValue (Join-Path $capPath "webcam") "Value" },
    [PSCustomObject]@{ Area="Microphone"; OrgPolicy=Get-NeoRegValue $appPrivacyPath "LetAppsAccessMicrophone"; UserValue=Get-NeoRegValue (Join-Path $capPath "microphone") "Value" },
    [PSCustomObject]@{ Area="Location"; OrgPolicy=Get-NeoRegValue $appPrivacyPath "LetAppsAccessLocation"; UserValue=Get-NeoRegValue (Join-Path $capPath "location") "Value" }
)

$review = [PSCustomObject]@{
    captured_at = (Get-Date).ToString("o")
    sensitive_permissions = $sensitivePolicies
    telemetry_allow_diagnostic_data = Get-NeoRegValue $dataPath "AllowTelemetry"
    location_disable_location = Get-NeoRegValue $locationPath "DisableLocation"
    location_disable_sensors = Get-NeoRegValue $locationPath "DisableSensors"
    activity_history_publish = Get-NeoRegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities"
    advertising_id = Get-NeoRegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled"
}

Write-Step "CAMERA / MICROPHONE / LOCATION"
Write-Host ""
foreach ($item in $sensitivePolicies) {
    if ($null -eq $item.OrgPolicy) {
        Write-OK ("{0}: user-controlled; no organization AppPrivacy lock detected." -f $item.Area)
    } elseif ([int]$item.OrgPolicy -eq 2) {
        Write-Warn ("{0}: BLOCKED by organization policy value 2. NeoOptimize will not set this." -f $item.Area)
    } else {
        Write-Info ("{0}: organization policy value={1}; user consent={2}" -f $item.Area, $item.OrgPolicy, $item.UserValue)
    }
}

if ($null -ne $review.location_disable_location -or $null -ne $review.location_disable_sensors) {
    Write-Warn "Location/Sensors organization policy is present. Review before assuming user-controlled privacy."
} else {
    Write-OK "No LocationAndSensors organization lock detected."
}

Write-Host ""
Write-Step "TELEMETRY / ADVERTISING"
Write-Host ""
Write-Info ("AllowTelemetry policy: {0}" -f $(if ($null -eq $review.telemetry_allow_diagnostic_data) { "not configured" } else { $review.telemetry_allow_diagnostic_data }))
Write-Info ("Advertising ID user setting: {0}" -f $(if ($null -eq $review.advertising_id) { "not configured" } else { $review.advertising_id }))

$dir = Join-Path $Global:LogDir "privacy"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$path = Join-Path $dir ("privacy-review_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$review | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding UTF8
Write-OK "Privacy review report: $path"
Write-Footer
Wait-AnyKey
