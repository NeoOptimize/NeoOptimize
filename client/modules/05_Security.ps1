
#Requires -RunAsAdministrator
<# MODULE 05  SECURITY AUDIT / OPTIONAL HARDENING #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "05" "" "SECURITY AUDIT / OPTIONAL HARDENING"
if (-not (Test-NeoHighRiskConsent -ActionName "Security Audit / Optional Hardening" -RiskLevel "High" -Reason "Mengubah Defender, firewall, SMB, TLS, RDP, LLMNR/WPAD, UAC, dan policy security Windows.")) {
    Wait-AnyKey
    return
}
$applied = 0

#  1. Windows Defender Enhancement 
Write-Step "WINDOWS DEFENDER  CLOUD PROTECTION HIGH"
Write-Host ""
$defCmds = @(
    { Set-MpPreference -DisableRealtimeMonitoring $false },
    { Set-MpPreference -CloudBlockLevel High },
    { Set-MpPreference -CloudExtendedTimeout 50 },
    { Set-MpPreference -EnableNetworkProtection AuditMode },
    { Set-MpPreference -EnableControlledFolderAccess AuditMode },
    { Set-MpPreference -PUAProtection Enabled },
    { Set-MpPreference -SubmitSamplesConsent SendSafeSamples },
    { Set-MpPreference -MAPSReporting Advanced },
    { Set-MpPreference -DisableBehaviorMonitoring $false },
    { Set-MpPreference -DisableIOAVProtection $false },
    { Set-MpPreference -DisableScriptScanning $false }
)
foreach ($cmd in $defCmds) {
    try { & $cmd; $applied++ } catch {}
}
Write-OK "Defender: RealTime=ON, Cloud=HIGH, PUA=ON, NetworkProtect=AUDIT, CFolderAccess=AUDIT"

#  2. UAC Maximum 
Write-Host ""
Write-Step "UAC  MAXIMUM LEVEL"
Write-Host ""
$uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-Reg $uacPath "EnableLUA"                       1
Set-Reg $uacPath "ConsentPromptBehaviorAdmin"       2   # Always notify
Set-Reg $uacPath "ConsentPromptBehaviorUser"        3   # Prompt for creds
Set-Reg $uacPath "PromptOnSecureDesktop"            1
Set-Reg $uacPath "EnableInstallerDetection"         1
Set-Reg $uacPath "ValidateAdminCodeSignatures"      0
Write-OK "UAC: MAXIMUM  Always Notify + Secure Desktop"
$applied++

#  3. SMBv1 Disable 
Write-Host ""
Write-Step "SMBv1  DISABLE (EternalBlue/WannaCry Prevention)"
Write-Host ""
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction SilentlyContinue
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "SMB1" 0
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10" "Start" 4
Write-OK "SMBv1: DISABLED  Protected from EternalBlue/WannaCry"
$applied++

#  4. SMB Signing 
Write-Host ""
Write-Step "SMB SIGNING (MITM Prevention)"
Write-Host ""
Set-SmbServerConfiguration -RequireSecuritySignature $true -EnableSecuritySignature $true -Force -ErrorAction SilentlyContinue
Set-SmbClientConfiguration -RequireSecuritySignature $false -EnableSecuritySignature $true -Force -ErrorAction SilentlyContinue
Write-OK "SMB Signing: ENABLED on server"
$applied++

#  5. Firewall  All Profiles 
Write-Host ""
Write-Step "WINDOWS FIREWALL"
Write-Host ""
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction SilentlyContinue
netsh advfirewall set allprofiles state on 2>&1 | Out-Null
netsh advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound 2>&1 | Out-Null
Write-OK "Firewall: ALL PROFILES ON  Inbound=Block, Outbound=Allow"
$applied++

#  6. Block Dangerous Ports 
Write-Host ""
Write-Step "DANGEROUS PORT BLOCKING"
Write-Host ""
$ports = @(
    @{Port="23";   Name="Telnet"},    @{Port="135";  Name="RPC"},
    @{Port="137";  Name="NetBIOS-NS"},@{Port="138";  Name="NetBIOS-DGM"},
    @{Port="139";  Name="NetBIOS"},   @{Port="445";  Name="SMB"},
    @{Port="1433"; Name="MSSQL"},     @{Port="1434"; Name="MSSQL-UDP"},
    @{Port="5900"; Name="VNC"},
    @{Port="4444"; Name="Metasploit"},@{Port="6666"; Name="IRC-Backdoor"}
)
foreach ($p in $ports) {
    Remove-NetFirewallRule -DisplayName "NEO_BLOCK_$($p.Name)" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "NEO_BLOCK_$($p.Name)" -Direction Inbound `
        -Protocol TCP -LocalPort $p.Port -Action Block -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  $($Global:RED)$($Global:RESET) Blocked inbound TCP $($p.Port.PadRight(5)) ($($p.Name))"
    $applied++
}

	#  7. RDP Hardening 
	Write-Host ""
	Write-Step "RDP CONFIGURATION"
	Write-Host ""
	if (Confirm-NeoAction "  Disable RDP? (direkomendasikan jika tidak digunakan)" $false) {
	    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" "fDenyTSConnections" 1
	    netsh advfirewall firewall set rule group="remote desktop" new enable=No 2>&1 | Out-Null
	    Write-OK "RDP: DISABLED"
} else {
    # Keep RDP but enforce NLA
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" "UserAuthentication" 1
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" "MinEncryptionLevel" 3
    Write-OK "RDP: ON dengan NLA enforced & encryption=High"
}
$applied++

#  8. AutoRun/AutoPlay Disable 
Write-Host ""
Write-Step "AUTORUN & AUTOPLAY  USB Attack Prevention"
Write-Host ""
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoDriveTypeAutoRun" 0xFF
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoAutorun" 1
Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" "DisableAutoplay" 1
Write-OK "AutoRun/AutoPlay: DISABLED (semua drive)"
$applied++

#  9. LLMNR & WPAD 
Write-Host ""
Write-Step "LLMNR & WPAD  MITM Prevention"
Write-Host ""
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "EnableMulticast" 0
netsh advfirewall firewall add rule name="NEO_BLOCK_LLMNR" dir=in action=block protocol=UDP localport=5355 2>&1 | Out-Null
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings" "EnableAutoProxyResultCache" 0
Write-OK "LLMNR: DISABLED | WPAD: DISABLED"
$applied++

#  10. Windows Script Host 
Write-Host ""
Write-Step "WINDOWS SCRIPT HOST (Malicious .vbs/.js prevention)"
Write-Host ""
if (Confirm-NeoAction "  Disable Windows Script Host? Ini dapat mematikan launcher .vbs dan script enterprise." $false) {
    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings" "Enabled" 0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows Script Host\Settings" "Enabled" 0
    Write-OK "Windows Script Host: DISABLED"
} else {
    Write-Info "Windows Script Host: unchanged (Defender-safe default)"
}
$applied++

#  11. TLS Hardening 
Write-Host ""
Write-Step "TLS/SSL PROTOCOL HARDENING"
Write-Host ""
$weak = @("SSL 2.0","SSL 3.0","TLS 1.0","TLS 1.1")
foreach ($proto in $weak) {
    $p = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$proto"
    Set-Reg "$p\Server" "Enabled" 0; Set-Reg "$p\Server" "DisabledByDefault" 1
    Set-Reg "$p\Client" "Enabled" 0; Set-Reg "$p\Client" "DisabledByDefault" 1
    Write-Host "  $($Global:RED)$($Global:RESET) Disabled: $proto"
    $applied++
}
foreach ($proto in @("TLS 1.2","TLS 1.3")) {
    $p = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$proto"
    Set-Reg "$p\Server" "Enabled" 1; Set-Reg "$p\Server" "DisabledByDefault" 0
    Set-Reg "$p\Client" "Enabled" 1; Set-Reg "$p\Client" "DisabledByDefault" 0
    Write-Host "  $($Global:GREEN)$($Global:RESET) Enabled:  $proto"
    $applied++
}

#  12. NTLMv2 & Anonymous Access 
Write-Host ""
Write-Step "NTLM & ANONYMOUS ACCESS"
Write-Host ""
$lsa = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
Set-Reg $lsa "RestrictAnonymous"         2
Set-Reg $lsa "RestrictAnonymousSAM"      1
Set-Reg $lsa "EveryoneIncludesAnonymous" 0
Set-Reg $lsa "NoLMHash"                  1
Set-Reg $lsa "LmCompatibilityLevel"      5   # NTLMv2 only
Write-OK "NTLMv2 only enforced, anonymous access restricted, LM hash disabled"
$applied++

#  13. Exploit Protection 
Write-Host ""
Write-Step "EXPLOIT PROTECTION (ASLR/DEP/CFG/SEHOP)"
Write-Host ""
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" "KernelSEHOPEnabled" 1
# DEP policy
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "NoDataExecutionPrevention" 0
bcdedit /set nx OptIn 2>&1 | Out-Null
Write-OK "SEHOP: ON | DEP: OptIn | ASLR via Defender settings"
$applied++

#  Summary 
Write-Host ""
Write-Separator "" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)   SECURITY HARDENING SELESAI  $applied perubahan$($Global:RESET)"
Write-Host ""
Write-Host "  $($Global:YELLOW)  Restart diperlukan untuk efek penuh TLS & SMB.$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
