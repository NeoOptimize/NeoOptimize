#Requires -RunAsAdministrator
<# MODULE 03  PRIVACY & TELEMETRY KILLER #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "03" "" "PRIVACY & TELEMETRY KILLER"
if (-not (Test-NeoHighRiskConsent -ActionName "Privacy & Telemetry" -RiskLevel "High" -Reason "Mengubah policy privacy, service diagnostic, AppX, hosts file, OneDrive, dan app permissions.")) {
    Wait-AnyKey
    return
}

$applied = 0

# 1. Telemetry Core
Write-Step "TELEMETRY & DATA COLLECTION"
Write-Host ""
$telRegs = @(
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",             "AllowTelemetry",                              0),
    @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection","AllowTelemetry",                            0),
    @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection","MaxTelemetryAllowed",                       0),
    @("HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Policies\DataCollection","AllowTelemetry",                0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",             "DoNotShowFeedbackNotifications",              1),
    @("HKCU:\SOFTWARE\Microsoft\Siuf\Rules",                                  "NumberOfSIUFInPeriod",                        0),
    @("HKCU:\SOFTWARE\Microsoft\Siuf\Rules",                                  "PeriodInNanoSeconds",                         0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows",                  "CEIPEnable",                                  0),
    @("HKLM:\SOFTWARE\Microsoft\SQMClient\Windows",                           "CEIPEnable",                                  0)
)
foreach ($r in $telRegs) { if (Set-Reg $r[0] $r[1] $r[2]) { $applied++ } }
Write-OK "Telemetry core policies: DISABLED"

# 2. Diagnostic Services
Write-Host ""
Write-Step "DIAGNOSTIC SERVICES"
Write-Host ""
$diagSvcs = @(
    @{N="DiagTrack";       D="Connected User Experiences & Telemetry"},
    @{N="dmwappushservice";D="WAP Push Message Routing"},
    @{N="PcaSvc";          D="Program Compatibility Assistant"},
    @{N="WerSvc";          D="Windows Error Reporting"},
    @{N="wercplsupport";   D="WER Control Panel Support"},
    @{N="diagnosticshub.standardcollector.service"; D="Diagnostics Hub Collector"}
)
foreach ($s in $diagSvcs) { Set-ServiceState $s.N "Disabled" $true $s.D }

# 3. Cortana Search
Write-Host ""
Write-Step "CORTANA & BING SEARCH INTEGRATION"
Write-Host ""
$cortana = @(
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search","AllowCortana",0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search","AllowCortanaAboveLock",0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search","DisableWebSearch",1),
    @("HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search","CortanaEnabled",0),
    @("HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search","BingSearchEnabled",0),
    @("HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search","SearchboxTaskbarMode",1)
)
foreach ($r in $cortana) { Set-Reg $r[0] $r[1] $r[2] | Out-Null }
Backup-RegKey "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" | Out-Null
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowSearchToUseLocation" -ErrorAction SilentlyContinue
Get-AppxPackage -Name "Microsoft.549981C3F5F10" -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
Write-OK "Cortana: DISABLED + Cortana AppX removed"
$applied++

# 4. Advertising & Tracking
Write-Host ""
Write-Step "ADVERTISING ID & TRACKING"
Write-Host ""
$ads = @(
    @("HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo","Enabled",0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo","DisabledByGroupPolicy",1),
    @("HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy","TailoredExperiencesWithDiagnosticDataEnabled",0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\System","EnableActivityFeed",0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\System","PublishUserActivities",0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\System","UploadUserActivities",0)
)
foreach ($r in $ads) { Set-Reg $r[0] $r[1] $r[2] | Out-Null }
Write-OK "Advertising ID & Activity Tracking: DISABLED"
$applied++

# 5. App Privacy Permissions
Write-Host ""
Write-Step "APP PRIVACY PERMISSIONS"
Write-Host ""
$privPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
Backup-RegKey $privPath | Out-Null
foreach ($k in @("LetAppsAccessCamera", "LetAppsAccessMicrophone", "LetAppsAccessLocation")) {
    Remove-ItemProperty -Path $privPath -Name $k -ErrorAction SilentlyContinue
}
$privKeys = @(
    "LetAppsAccessContacts","LetAppsAccessCalendar","LetAppsAccessCallHistory",
    "LetAppsAccessEmail","LetAppsAccessAccountInfo","LetAppsAccessMessaging",
    "LetAppsAccessPhone","LetAppsRunInBackground","LetAppsAccessMotion",
    "LetAppsAccessTasks","LetAppsAccessUserAccountMovement"
)
foreach ($k in $privKeys) { Set-Reg $privPath $k 2 | Out-Null }
Write-OK "Camera/Microphone/Location tetap user-controlled, tidak dikunci policy organisasi"
Write-OK "App permissions lain restricted (Contacts/Calendar/Call History/...)"
$applied += $privKeys.Count

# 6. Location Services
Write-Host ""
Write-Step "LOCATION SERVICES"
Write-Host ""
$locPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
Backup-RegKey $locPath | Out-Null
foreach ($k in @("DisableLocation", "DisableLocationScripting", "DisableSensors")) {
    Remove-ItemProperty -Path $locPath -Name $k -ErrorAction SilentlyContinue
}
try { Set-Service -Name "lfsvc" -StartupType Manual -ErrorAction SilentlyContinue } catch {}
Write-OK "Location policy override removed; Location remains user-controlled"
$applied++

# 7. Telemetry Endpoint Hosts Blocks
Write-Host ""
Write-Step "TELEMETRY ENDPOINTS  HOSTS BLOCK"
Write-Host ""
$endpoints = @(
    "vortex.data.microsoft.com","vortex-win.data.microsoft.com",
    "telecommand.telemetry.microsoft.com","oca.telemetry.microsoft.com",
    "sqm.telemetry.microsoft.com","watson.telemetry.microsoft.com",
    "redir.metaservices.microsoft.com","choice.microsoft.com",
    "df.telemetry.microsoft.com","telemetry.microsoft.com",
    "watson.ppe.telemetry.microsoft.com","settings-sandbox.data.microsoft.com",
    "vortex-sandbox.data.microsoft.com","survey.watson.microsoft.com",
    "reports.wes.df.telemetry.microsoft.com","services.wes.df.telemetry.microsoft.com",
    "sqm.df.telemetry.microsoft.com","pipe.aria.microsoft.com",
    "browser.pipe.aria.microsoft.com","self.events.data.microsoft.com"
)
foreach ($ep in $endpoints) {
    Remove-NeoFirewallRule "NEO_BLOCK_$ep" | Out-Null
}
if (Add-HostsBlock "Telemetry" $endpoints) {
    Write-OK "Telemetry endpoints diblokir via hosts file"
    $applied++
}

# 8. Cloud & Clipboard
Write-Host ""
Write-Step "CLOUD SYNC & ONEDRIVE"
Write-Host ""
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "AllowClipboardHistory" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "AllowCrossDeviceClipboard" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" 1
Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue
Write-OK "Cloud Clipboard: DISABLED"
Write-OK "OneDrive Auto-Start: DISABLED"
$applied += 2

# 9. Content Delivery & Spotlight
Write-Host ""
Write-Step "TIPS, SUGGESTIONS & SPOTLIGHT"
Write-Host ""
$cdmPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
$cdmKeys = @(
    "SubscribedContent-338387Enabled","SubscribedContent-338388Enabled",
    "SubscribedContent-353698Enabled","SubscribedContent-310093Enabled",
    "SystemPaneSuggestionsEnabled","SilentInstalledAppsEnabled",
    "SoftLandingEnabled","RotatingLockScreenEnabled",
    "ContentDeliveryAllowed","OemPreInstalledAppsEnabled",
    "PreInstalledAppsEnabled","PreInstalledAppsEverEnabled"
)
foreach ($k in $cdmKeys) { Set-Reg $cdmPath $k 0 | Out-Null }
Write-OK "Content suggestions, tips & spotlight: DISABLED"
$applied++

# 10. Next-Gen Selectable Debloater
Write-Host ""
Write-Step "SELECTABLE UWP BLOATWARE REMOVAL"
Write-Host ""
$debloatCount = Invoke-SelectableDebloater
$applied += $debloatCount

# Refresh Cached Health Results
try {
    $Global:NeoHealthResult = Invoke-NeoHealthScreening -Run $true
} catch {}

# Summary
Write-Host ""
Write-Separator "" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)   PRIVACY & TELEMETRY KILLER SELESAI  $applied perubahanApplied$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
