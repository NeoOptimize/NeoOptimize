#Requires -RunAsAdministrator
<# MODULE 24 - DEVICE SNAPSHOT #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "24" "HW" "DEVICE SNAPSHOT"

$dir = Join-Path $Global:LogDir "device"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"

function Select-NeoCimObject {
    param($InputObject, [string[]]$Property)
    if ($null -eq $InputObject) { return $null }
    return $InputObject | Select-Object -Property $Property
}

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpus = @(Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, AdapterRAM, VideoProcessor, CurrentHorizontalResolution, CurrentVerticalResolution)
$memory = @(Get-CimInstance Win32_PhysicalMemory | Select-Object BankLabel, Manufacturer, PartNumber, Speed, Capacity)
$physicalDisks = @(Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus, Size)
$volumes = @(Get-Volume | Select-Object DriveLetter, FileSystemLabel, FileSystem, DriveType, HealthStatus, OperationalStatus, Size, SizeRemaining)
$adapters = @(Get-NetAdapter | Select-Object Name, Status, LinkSpeed, MacAddress, InterfaceDescription)
$problemDevices = @(Get-PnpDevice | Where-Object { $_.Status -notin @("OK", "Unknown") -or $_.Problem -gt 0 } | Select-Object Class, FriendlyName, InstanceId, Status, Problem)

$secureBoot = "Unavailable"
try { $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop } catch { $secureBoot = "UnavailableOrLegacyBIOS" }

$snapshot = [PSCustomObject]@{
    captured_at = (Get-Date).ToString("o")
    computer = Select-NeoCimObject $cs @("Manufacturer", "Model", "Domain", "TotalPhysicalMemory", "NumberOfLogicalProcessors", "HypervisorPresent")
    operating_system = Select-NeoCimObject $os @("Caption", "Version", "BuildNumber", "OSArchitecture", "InstallDate", "LastBootUpTime")
    bios = Select-NeoCimObject $bios @("Manufacturer", "SMBIOSBIOSVersion", "SerialNumber", "ReleaseDate")
    cpu = Select-NeoCimObject $cpu @("Name", "NumberOfCores", "NumberOfLogicalProcessors", "VirtualizationFirmwareEnabled", "SecondLevelAddressTranslationExtensions")
    gpu = $gpus
    memory_modules = $memory
    physical_disks = $physicalDisks
    volumes = $volumes
    network_adapters = $adapters
    problem_devices = $problemDevices
    tpm = (Get-Tpm | Select-Object TpmPresent, TpmReady, TpmEnabled, ManufacturerIdTxt)
    secure_boot = $secureBoot
    bitlocker = @(Get-BitLockerVolume | Select-Object MountPoint, VolumeStatus, ProtectionStatus, EncryptionPercentage)
}

Write-Step "DEVICE SUMMARY"
Write-Host ""
Write-Info ("Computer: {0} {1}" -f $cs.Manufacturer, $cs.Model)
Write-Info ("Windows : {0} build {1} ({2})" -f $os.Caption, $os.BuildNumber, $os.OSArchitecture)
Write-Info ("CPU     : {0}" -f $cpu.Name)
Write-Info ("RAM     : {0} GB" -f ([math]::Round($cs.TotalPhysicalMemory / 1GB, 1)))
Write-Info ("GPU     : {0}" -f (($gpus | Select-Object -ExpandProperty Name) -join "; "))
Write-Info ("Disks   : {0}" -f $physicalDisks.Count)
Write-Info ("Network : {0}" -f $adapters.Count)
if ($problemDevices.Count -gt 0) {
    Write-Warn ("Problem devices detected: {0}" -f $problemDevices.Count)
} else {
    Write-OK "No problem devices reported by PnP."
}

$jsonPath = Join-Path $dir ("device-snapshot_{0}.json" -f $stamp)
$txtPath = Join-Path $dir ("device-snapshot_{0}.txt" -f $stamp)
$snapshot | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8
$snapshot | Format-List * | Out-String | Set-Content -Path $txtPath -Encoding UTF8

Write-OK "Device snapshot JSON: $jsonPath"
Write-OK "Device snapshot text: $txtPath"
Write-Footer
Wait-AnyKey
