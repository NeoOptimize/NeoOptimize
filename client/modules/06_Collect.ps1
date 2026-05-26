#Requires -RunAsAdministrator
<#
.SYNOPSIS  NeoOptimize - Hardware Telemetry & Device Info Collector v4.0
.DESCRIPTION
    Deep system telemetry and hardware profiling:
    - Complete hardware inventory (CPU/GPU/RAM/Disk/NIC)
    - Battery and power profile info
    - Installed software & license keys
    - Running services and processes snapshot
    - Windows license and activation status
    - System performance benchmark
    - Reports as structured JSON to RMM
#>

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference    = "SilentlyContinue"

Write-Host "`n[COLLECT] =================================================" -ForegroundColor Cyan
Write-Host "[COLLECT]  Hardware Telemetry & Device Info Collector v4.0 " -ForegroundColor Cyan
Write-Host "[COLLECT] =================================================`n" -ForegroundColor Cyan

$report = [ordered]@{ timestamp = (Get-Date).ToString("o") }

# ─── SECTION 1: OS & System Info ─────────────────────────────────────────────
Write-Host "  [1/8] Collecting OS & system information..." -ForegroundColor Yellow

$os  = Get-CimInstance Win32_OperatingSystem
$cs  = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$tz  = [System.TimeZoneInfo]::Local

$report.system = [ordered]@{
    hostname       = $env:COMPUTERNAME
    domain         = $env:USERDOMAIN
    manufacturer   = $cs.Manufacturer
    model          = $cs.Model
    os             = $os.Caption
    os_version     = $os.Version
    os_build       = $os.BuildNumber
    os_arch        = $os.OSArchitecture
    os_install_date= $os.InstallDate.ToString("yyyy-MM-dd")
    last_boot      = $os.LastBootUpTime.ToString("o")
    uptime_hours   = [math]::Round((New-TimeSpan $os.LastBootUpTime).TotalHours, 1)
    bios_version   = $bios.SMBIOSBIOSVersion
    bios_date      = $bios.ReleaseDate.ToString("yyyy-MM-dd")
    serial_number  = $bios.SerialNumber
    timezone       = $tz.DisplayName
    locale         = [System.Globalization.CultureInfo]::CurrentCulture.Name
    logged_users   = (Get-WmiObject Win32_LoggedOnUser -EA SilentlyContinue | Select-Object -ExpandProperty Antecedent | ForEach-Object { ($_ -split '"')[1] } | Select-Object -Unique) -join ", "
}

Write-Host "    [+] OS: $($os.Caption) ($($os.OSArchitecture))" -ForegroundColor Green
Write-Host "    [+] Model: $($cs.Manufacturer) $($cs.Model)" -ForegroundColor Green

# ─── SECTION 2: CPU Information ──────────────────────────────────────────────
Write-Host "`n  [2/8] Collecting CPU information..." -ForegroundColor Yellow

$cpus = Get-CimInstance Win32_Processor
$report.cpu = $cpus | ForEach-Object {
    [ordered]@{
        name          = $_.Name.Trim()
        manufacturer  = $_.Manufacturer
        cores         = $_.NumberOfCores
        threads       = $_.NumberOfLogicalProcessors
        speed_mhz     = $_.MaxClockSpeed
        socket        = $_.SocketDesignation
        L2_cache_kb   = $_.L2CacheSize
        L3_cache_kb   = $_.L3CacheSize
        virtualization= $_.VirtualizationFirmwareEnabled
        load_pct      = $_.LoadPercentage
    }
}

$cpuName = $cpus[0].Name.Trim()
Write-Host "    [+] CPU: $cpuName ($($cpus[0].NumberOfCores)C/$($cpus[0].NumberOfLogicalProcessors)T)" -ForegroundColor Green

# ─── SECTION 3: RAM Information ──────────────────────────────────────────────
Write-Host "`n  [3/8] Collecting RAM information..." -ForegroundColor Yellow

$ramModules = Get-CimInstance Win32_PhysicalMemory
$totalRam   = ($ramModules | Measure-Object Capacity -Sum).Sum / 1GB
$usedRam    = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB

$report.ram = [ordered]@{
    total_gb    = [math]::Round($totalRam, 1)
    used_gb     = [math]::Round($usedRam / 1024, 2)
    slots_used  = $ramModules.Count
    modules     = $ramModules | ForEach-Object {
        [ordered]@{
            slot         = $_.DeviceLocator
            size_gb      = [math]::Round($_.Capacity / 1GB, 0)
            speed_mhz    = $_.ConfiguredClockSpeed
            type         = switch ($_.MemoryType) { 20{"DDR"} 21{"DDR2"} 24{"DDR3"} 26{"DDR4"} 34{"DDR5"} default{"Unknown"} }
            manufacturer = $_.Manufacturer
            part_number  = $_.PartNumber.Trim()
            serial       = $_.SerialNumber
        }
    }
}

Write-Host "    [+] RAM: $([math]::Round($totalRam,1)) GB across $($ramModules.Count) module(s)" -ForegroundColor Green

# ─── SECTION 4: GPU Information ──────────────────────────────────────────────
Write-Host "`n  [4/8] Collecting GPU information..." -ForegroundColor Yellow

$gpus = Get-CimInstance Win32_VideoController
$report.gpu = $gpus | ForEach-Object {
    [ordered]@{
        name          = $_.Name
        driver_version= $_.DriverVersion
        driver_date   = $_.DriverDate.ToString("yyyy-MM-dd")
        vram_mb       = [math]::Round($_.AdapterRAM / 1MB, 0)
        resolution    = "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"
        refresh_hz    = $_.CurrentRefreshRate
        adapter_type  = $_.AdapterDACType
        video_mode    = $_.VideoModeDescription
    }
}

foreach ($gpu in $gpus) { Write-Host "    [+] GPU: $($gpu.Name)" -ForegroundColor Green }

# ─── SECTION 5: Storage & Disk Info ──────────────────────────────────────────
Write-Host "`n  [5/8] Collecting disk & storage information..." -ForegroundColor Yellow

$disks = Get-CimInstance Win32_DiskDrive
$vols  = Get-Volume | Where-Object { $_.DriveType -eq "Fixed" -and $_.DriveLetter }

$report.storage = [ordered]@{
    physical_disks = $disks | ForEach-Object {
        [ordered]@{
            model       = $_.Model
            serial      = $_.SerialNumber
            interface   = $_.InterfaceType
            size_gb     = [math]::Round($_.Size / 1GB, 1)
            partitions  = $_.Partitions
            media_type  = $_.MediaType
        }
    }
    volumes = $vols | ForEach-Object {
        [ordered]@{
            letter      = $_.DriveLetter
            label       = $_.FileSystemLabel
            fs          = $_.FileSystem
            total_gb    = [math]::Round($_.Size / 1GB, 1)
            free_gb     = [math]::Round($_.SizeRemaining / 1GB, 1)
            used_pct    = if ($_.Size -gt 0) { [math]::Round((1 - $_.SizeRemaining / $_.Size) * 100, 1) } else { 0 }
        }
    }
}

Write-Host "    [+] Disks found: $($disks.Count)" -ForegroundColor Green
foreach ($v in $vols) {
    $freeGB = [math]::Round($v.SizeRemaining / 1GB, 1)
    Write-Host "    [+] Drive $($v.DriveLetter): Free $freeGB GB" -ForegroundColor Green
}

# ─── SECTION 6: Network Adapters ─────────────────────────────────────────────
Write-Host "`n  [6/8] Collecting network adapter information..." -ForegroundColor Yellow

$nics = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
try { $pubIP = (Invoke-RestMethod -Uri "https://api.ipify.org?format=json" -TimeoutSec 5).ip } catch { $pubIP = "N/A" }

$report.network = [ordered]@{
    public_ip    = $pubIP
    adapters     = $nics | ForEach-Object {
        $ip = Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -EA SilentlyContinue
        [ordered]@{
            name         = $_.Name
            description  = $_.InterfaceDescription
            mac          = $_.MacAddress
            speed        = $_.LinkSpeed
            ip_address   = $ip.IPAddress
            prefix       = $ip.PrefixLength
            dhcp         = (Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -EA SilentlyContinue).Dhcp -eq "Enabled"
        }
    }
}

Write-Host "    [+] Public IP: $pubIP" -ForegroundColor Green
foreach ($nic in $nics) { Write-Host "    [+] Adapter: $($nic.Name) @ $($nic.LinkSpeed)" -ForegroundColor Green }

# ─── SECTION 7: Installed Software ───────────────────────────────────────────
Write-Host "`n  [7/8] Enumerating installed software..." -ForegroundColor Yellow

$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$software = foreach ($path in $regPaths) {
    Get-ItemProperty $path -EA SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
}

$software = $software | Sort-Object DisplayName -Unique
$report.software_count = $software.Count
$report.software = $software | Select-Object -First 50 | ForEach-Object {
    [ordered]@{ name = $_.DisplayName; version = $_.DisplayVersion; publisher = $_.Publisher }
}

Write-Host "    [+] Installed programs: $($software.Count)" -ForegroundColor Green

# ─── SECTION 8: Windows License & Activation ─────────────────────────────────
Write-Host "`n  [8/8] Checking Windows license & activation..." -ForegroundColor Yellow

$licenseSvc = Get-WmiObject SoftwareLicensingService -EA SilentlyContinue
$licenseProduct = Get-WmiObject SoftwareLicensingProduct -EA SilentlyContinue | Where-Object { $_.Name -like "Windows*" -and $_.LicenseStatus -eq 1 }

$report.license = [ordered]@{
    product_name    = ($licenseProduct | Select-Object -First 1).Name
    license_status  = if ($licenseProduct) { "Licensed" } else { "Not Licensed" }
    partial_key     = $licenseSvc?.OA3xOriginalProductKey
}

Write-Host "    [+] License: $($report.license.license_status)" -ForegroundColor Green

# ─── OUTPUT ──────────────────────────────────────────────────────────────────
$jsonReport = $report | ConvertTo-Json -Depth 8 -Compress

# Save report locally
$reportPath = "$env:ProgramData\NeoOptimize\hardware_report.json"
$reportDir  = Split-Path $reportPath
if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
Set-Content -Path $reportPath -Value $jsonReport -Encoding UTF8

Write-Host "`n[COLLECT] =================================================" -ForegroundColor Cyan
Write-Host "[COLLECT]  Hardware report saved to: $reportPath" -ForegroundColor Green
Write-Host "[COLLECT]  Report size: $([math]::Round($jsonReport.Length / 1KB, 1)) KB" -ForegroundColor Green
Write-Host "[COLLECT] =================================================`n" -ForegroundColor Cyan

# Output JSON for RMM to capture
Write-Output "RESULT_JSON:$jsonReport"
