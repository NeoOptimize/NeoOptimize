#Requires -RunAsAdministrator
<# MODULE 36 - SECURITY AUDIT #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "36" "SEC" "SECURITY AUDIT"

function Get-NeoRegValue {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

$defender = Get-MpComputerStatus
$mpPref = Get-MpPreference
$firewall = @(Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction, NotifyOnListen)
$tpm = Get-Tpm
$secureBoot = "Unavailable"
try { $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop } catch { $secureBoot = "UnavailableOrLegacyBIOS" }
$uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$localAdmins = @(Get-LocalGroupMember -Group "Administrators" | Select-Object Name, ObjectClass, PrincipalSource)
$smb = Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, EnableSMB2Protocol, RequireSecuritySignature, EnableSecuritySignature
$bitlocker = @(Get-BitLockerVolume | Select-Object MountPoint, VolumeStatus, ProtectionStatus, EncryptionPercentage)

$report = [PSCustomObject]@{
    captured_at = (Get-Date).ToString("o")
    defender = $defender | Select-Object AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, BehaviorMonitorEnabled, IsTamperProtected, NISEnabled
    defender_preferences = $mpPref | Select-Object EnableControlledFolderAccess, EnableNetworkProtection, AttackSurfaceReductionRules_Ids, AttackSurfaceReductionRules_Actions
    firewall = $firewall
    tpm = $tpm | Select-Object TpmPresent, TpmReady, TpmEnabled, ManufacturerIdTxt
    secure_boot = $secureBoot
    uac = [PSCustomObject]@{
        EnableLUA = Get-NeoRegValue $uacPath "EnableLUA"
        ConsentPromptBehaviorAdmin = Get-NeoRegValue $uacPath "ConsentPromptBehaviorAdmin"
        PromptOnSecureDesktop = Get-NeoRegValue $uacPath "PromptOnSecureDesktop"
    }
    smb = $smb
    bitlocker = $bitlocker
    local_administrators = $localAdmins
}

Write-Step "DEFENDER / FIREWALL"
Write-Host ""
Write-Info ("Defender realtime : {0}" -f $defender.RealTimeProtectionEnabled)
Write-Info ("Tamper protection : {0}" -f $defender.IsTamperProtected)
foreach ($profile in $firewall) {
    Write-Info ("Firewall {0}: Enabled={1} Inbound={2}" -f $profile.Name, $profile.Enabled, $profile.DefaultInboundAction)
}

Write-Host ""
Write-Step "PLATFORM SECURITY"
Write-Host ""
Write-Info ("TPM present       : {0}" -f $tpm.TpmPresent)
Write-Info ("TPM ready         : {0}" -f $tpm.TpmReady)
Write-Info ("Secure Boot       : {0}" -f $secureBoot)
Write-Info ("BitLocker volumes : {0}" -f $bitlocker.Count)
Write-Info ("Local admins      : {0}" -f $localAdmins.Count)

$dir = Join-Path $Global:LogDir "security"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$path = Join-Path $dir ("security-audit_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
Write-OK "Security audit report: $path"
Write-Footer
Wait-AnyKey
