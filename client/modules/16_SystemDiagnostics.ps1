#Requires -Version 5.1
<#
.SYNOPSIS
    NeoOptimize Windows anomaly, boot, driver, and maintenance diagnostics.
.DESCRIPTION
    Report mode detects Windows health issues. Repair mode performs conservative
    maintenance: WinRE enable, DISM RestoreHealth, SFC scan, Windows Update
    component reset, and critical service restart attempts.
#>

param(
    [ValidateSet("Report", "Repair", "Full")]
    [string]$Mode = "Report",
    [int]$EventDays = 7,
    [string]$ArgsJson = ""
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

try { . "$PSScriptRoot\..\lib\Common.ps1" } catch {}

if ($ArgsJson) {
    try {
        $parsedArgs = $ArgsJson | ConvertFrom-Json
        if ($parsedArgs.Mode) { $Mode = [string]$parsedArgs.Mode }
        if ($parsedArgs.EventDays) { $EventDays = [int]$parsedArgs.EventDays }
    } catch {}
}

function Out-Info { param([string]$Message) if (Get-Command Write-Info -ErrorAction SilentlyContinue) { Write-Info $Message } else { Write-Host "  [*] $Message" -ForegroundColor Cyan } }
function Out-OK { param([string]$Message) if (Get-Command Write-OK -ErrorAction SilentlyContinue) { Write-OK $Message } elseif (Get-Command Write-Success -ErrorAction SilentlyContinue) { Write-Success $Message } else { Write-Host "  [+] $Message" -ForegroundColor Green } }
function Out-Warn { param([string]$Message) if (Get-Command Write-Warn -ErrorAction SilentlyContinue) { Write-Warn $Message } else { Write-Host "  [!] $Message" -ForegroundColor Yellow } }
function Out-Err { param([string]$Message) if (Get-Command Write-Err -ErrorAction SilentlyContinue) { Write-Err $Message } elseif (Get-Command Write-Fail -ErrorAction SilentlyContinue) { Write-Fail $Message } else { Write-Host "  [X] $Message" -ForegroundColor Red } }
function Out-Step { param([string]$Message) if (Get-Command Write-Step -ErrorAction SilentlyContinue) { Write-Step $Message } else { Write-Host "`n== $Message ==" -ForegroundColor Magenta } }

if (Get-Command Write-ModuleHeader -ErrorAction SilentlyContinue) {
    Write-ModuleHeader "16" "DIAG" "SYSTEM DIAGNOSTICS"
} elseif (Get-Command Write-NeoHeader -ErrorAction SilentlyContinue) {
    Write-NeoHeader "System Diagnostics" "1.1"
} else {
    Write-Host "`nNeoOptimize System Diagnostics v1.1`n" -ForegroundColor Cyan
}

$rootDir = Split-Path -Parent $PSScriptRoot
$reportDir = Join-Path $rootDir "reports\system_diagnostics"
if (-not (Test-Path $reportDir)) { New-Item -Path $reportDir -ItemType Directory -Force | Out-Null }
$reportPath = Join-Path $reportDir ("SystemDiagnostics_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

$Script:Findings = New-Object System.Collections.Generic.List[object]
$Script:Actions = New-Object System.Collections.Generic.List[object]
$Script:Score = 100

function Add-Finding {
    param(
        [string]$Id,
        [string]$Category,
        [ValidateSet("Critical", "High", "Medium", "Low", "Info")]
        [string]$Severity,
        [string]$Title,
        [string]$Detail,
        [string]$Recommendation
    )
    $penalty = switch ($Severity) {
        "Critical" { 25 }
        "High" { 15 }
        "Medium" { 8 }
        "Low" { 3 }
        default { 0 }
    }
    $Script:Score = [math]::Max(0, $Script:Score - $penalty)
    $Script:Findings.Add([PSCustomObject]@{
        id = $Id
        category = $Category
        severity = $Severity
        title = $Title
        detail = $Detail
        recommendation = $Recommendation
    }) | Out-Null
}

function Add-Action {
    param([string]$Name, [string]$Status, [string]$Detail)
    $Script:Actions.Add([PSCustomObject]@{
        name = $Name
        status = $Status
        detail = $Detail
        time = (Get-Date).ToString("o")
    }) | Out-Null
}

function Test-Admin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Test-RebootPending {
    $reasons = New-Object System.Collections.Generic.List[string]
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    )
    foreach ($path in $paths) {
        if (-not (Test-Path $path)) { continue }
        if ($path -like "*Session Manager") {
            $value = (Get-ItemProperty -Path $path -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
            if ($value) { $reasons.Add("PendingFileRenameOperations") | Out-Null }
        } else {
            $reasons.Add(($path -split "\\")[-1]) | Out-Null
        }
    }
    return @($reasons)
}

function Get-WinReState {
    $raw = ""
    try { $raw = (& reagentc.exe /info 2>&1) -join "`n" } catch {}
    $enabled = $null
    if ($raw -match "(?im)Windows RE status:\s*Enabled|Status Windows RE:\s*Enabled|Windows RE status:\s*Aktif") { $enabled = $true }
    elseif ($raw -match "(?im)Windows RE status:\s*Disabled|Status Windows RE:\s*Disabled|Windows RE status:\s*Nonaktif") { $enabled = $false }
    return [PSCustomObject]@{ enabled = $enabled; raw = $raw }
}

function Invoke-WinReCheck {
    Out-Step "Windows Recovery Environment"
    $state = Get-WinReState
    if ($state.enabled -eq $false) {
        Add-Finding "NEO-WINRE-001" "Boot" "High" "Windows Recovery Environment is disabled" "reagentc reports Disabled." "Run reagentc /enable so failed boot recovery works."
        if ($Mode -in @("Repair", "Full")) {
            try {
                $output = (& reagentc.exe /enable 2>&1) -join "`n"
                Add-Action "reagentc /enable" "attempted" $output
                $state = Get-WinReState
            } catch {
                Add-Action "reagentc /enable" "failed" $_.Exception.Message
            }
        }
    } elseif ($state.enabled -eq $true) {
        Out-OK "Windows RE is enabled"
    } else {
        Add-Finding "NEO-WINRE-002" "Boot" "Medium" "Windows Recovery Environment status could not be parsed" "reagentc output was unavailable or unexpected." "Run reagentc /info manually in an elevated terminal."
    }
    return $state
}

function Invoke-BootAudit {
    Out-Step "Boot configuration audit"
    $boot = [PSCustomObject]@{ current = ""; bootmgr = "" }
    try { $boot.current = (& bcdedit.exe /enum "{current}" 2>&1) -join "`n" } catch {}
    try { $boot.bootmgr = (& bcdedit.exe /enum "{bootmgr}" 2>&1) -join "`n" } catch {}

    $combined = "$($boot.current)`n$($boot.bootmgr)"
    if ($combined -match "(?im)safeboot\s+\w+") {
        Add-Finding "NEO-BOOT-001" "Boot" "Critical" "Safe boot flag is set" "BCD contains safeboot." "Remove safeboot after maintenance if normal boot is expected."
    }
    if ($combined -match "(?im)testsigning\s+Yes|testsigning\s+on") {
        Add-Finding "NEO-BOOT-002" "Boot" "High" "Test signing is enabled" "BCD testsigning is enabled." "Disable testsigning unless this is an intentional driver lab."
    }
    if ($combined -match "(?im)nointegritychecks\s+Yes|nointegritychecks\s+on") {
        Add-Finding "NEO-BOOT-003" "Boot" "Critical" "Driver integrity checks are disabled" "BCD nointegritychecks is enabled." "Re-enable integrity checks for production endpoints."
    }
    if ($combined -match "(?im)recoveryenabled\s+No") {
        Add-Finding "NEO-BOOT-004" "Boot" "High" "Boot recovery is disabled" "BCD recoveryenabled is No." "Enable recovery for safer failed-boot handling."
    }
    if ($combined -match "(?im)bootstatuspolicy\s+IgnoreAllFailures") {
        Add-Finding "NEO-BOOT-005" "Boot" "Medium" "Boot status failures are ignored" "BCD bootstatuspolicy ignores failures." "Use default boot status policy for production troubleshooting."
    }
    return $boot
}

function Invoke-DriverAudit {
    Out-Step "Driver and device anomaly audit"
    $problemDevices = @()
    try {
        $problemDevices = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -and $_.Status -ne "OK"
        } | Select-Object -First 100 Status, Class, FriendlyName, InstanceId, Problem)
    } catch {}

    if ($problemDevices.Count -gt 0) {
        Add-Finding "NEO-DRV-001" "Driver" "High" "Problem devices detected" "$($problemDevices.Count) devices are not OK." "Open Device Manager or update/reinstall the affected drivers."
    } else {
        Out-OK "No PnP problem devices found"
    }

    $signedIssues = @()
    try {
        $signedIssues = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
            Where-Object { $_.DeviceName -and ($_.IsSigned -eq $false -or $_.DriverProviderName -match "Unknown") } |
            Select-Object -First 100 DeviceName, DriverProviderName, DriverVersion, IsSigned, InfName)
    } catch {}

    if ($signedIssues.Count -gt 0) {
        Add-Finding "NEO-DRV-002" "Driver" "Medium" "Unsigned or unknown driver providers found" "$($signedIssues.Count) signed-driver records look suspicious or incomplete." "Review drivers before production distribution."
    }

    return [PSCustomObject]@{
        problem_devices = @($problemDevices)
        unsigned_or_unknown = @($signedIssues)
    }
}

function Invoke-EventAudit {
    Out-Step "Windows error event audit"
    $start = (Get-Date).AddDays(-1 * [math]::Abs($EventDays))
    $logs = @("System", "Application", "Microsoft-Windows-WindowsUpdateClient/Operational")
    $events = New-Object System.Collections.Generic.List[object]

    foreach ($log in $logs) {
        try {
            $items = Get-WinEvent -FilterHashtable @{ LogName = $log; Level = 1,2,3; StartTime = $start } -MaxEvents 250 -ErrorAction SilentlyContinue
            foreach ($evt in $items) {
                $message = ([string]$evt.Message -replace "\s+", " ").Trim()
                $sampleLength = [math]::Min(240, $message.Length)
                $events.Add([PSCustomObject]@{
                    log = $log
                    provider = $evt.ProviderName
                    id = $evt.Id
                    level = $evt.LevelDisplayName
                    time = $evt.TimeCreated
                    message = $message.Substring(0, $sampleLength)
                }) | Out-Null
            }
        } catch {}
    }

    $driverProviders = "Disk|Ntfs|storahci|stornvme|iaStor|WHEA-Logger|Display|nvlddmkm|amdkmdag|Kernel-PnP|DriverFrameworks"
    $driverEvents = @($events | Where-Object { $_.provider -match $driverProviders })
    $bootEvents = @($events | Where-Object { $_.provider -match "Kernel-Boot|Kernel-Power|EventLog" -or $_.id -in @(41, 6008, 29, 30) })
    $updateEvents = @($events | Where-Object { $_.provider -match "WindowsUpdateClient" })

    if ($driverEvents.Count -gt 0) {
        Add-Finding "NEO-EVT-DRV" "EventLog" "High" "Driver/storage/hardware errors detected" "$($driverEvents.Count) driver or hardware related events in the last $EventDays days." "Review top event providers and update affected drivers."
    }
    if ($bootEvents.Count -gt 0) {
        Add-Finding "NEO-EVT-BOOT" "EventLog" "Medium" "Boot or power anomalies detected" "$($bootEvents.Count) boot/power events in the last $EventDays days." "Check shutdown history, PSU/battery, and boot configuration."
    }
    if ($updateEvents.Count -gt 0) {
        Add-Finding "NEO-EVT-WU" "EventLog" "Medium" "Windows Update errors detected" "$($updateEvents.Count) update-client warnings/errors in the last $EventDays days." "Run Windows Update reset during a maintenance window."
    }

    $top = @($events | Group-Object provider, id | Sort-Object Count -Descending | Select-Object -First 20 | ForEach-Object {
        [PSCustomObject]@{
            key = $_.Name
            count = $_.Count
            sample = $_.Group[0].message
        }
    })

    return [PSCustomObject]@{
        total = $events.Count
        top = @($top)
        driver_events = @($driverEvents | Select-Object -First 50)
        boot_events = @($bootEvents | Select-Object -First 50)
        update_events = @($updateEvents | Select-Object -First 50)
    }
}

function Invoke-ServiceAudit {
    Out-Step "Critical service audit"
    $critical = @("EventLog", "PlugPlay", "RpcSs", "BFE", "mpssvc", "WinDefend", "Dnscache", "Winmgmt", "wuauserv", "bits", "cryptsvc")
    $states = New-Object System.Collections.Generic.List[object]
    foreach ($name in $critical) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        $states.Add([PSCustomObject]@{ name = $name; display = $svc.DisplayName; status = [string]$svc.Status; start_type = (Get-CimInstance Win32_Service -Filter "Name='$name'").StartMode }) | Out-Null
        if ($svc.Status -ne "Running" -and $name -in @("EventLog", "PlugPlay", "RpcSs", "BFE", "mpssvc", "WinDefend", "Dnscache", "Winmgmt")) {
            Add-Finding "NEO-SVC-$name" "Service" "High" "Critical service is not running" "$name is $($svc.Status)." "Start the service and verify dependent Windows components."
            if ($Mode -in @("Repair", "Full")) {
                try {
                    Start-Service -Name $name -ErrorAction Stop
                    Add-Action "Start-Service $name" "success" "Service start requested."
                } catch {
                    Add-Action "Start-Service $name" "failed" $_.Exception.Message
                }
            }
        }
    }
    return @($states)
}

function Invoke-DiskAudit {
    Out-Step "Disk health audit"
    $volumes = @()
    try {
        $volumes = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | Select-Object DriveLetter, FileSystemLabel, FileSystem, DriveType, HealthStatus, Size, SizeRemaining)
    } catch {}

    foreach ($vol in $volumes) {
        if (-not $vol.Size -or $vol.DriveType -ne "Fixed") { continue }
        $freePct = [math]::Round(($vol.SizeRemaining / $vol.Size) * 100, 1)
        if ($freePct -lt 5) {
            Add-Finding "NEO-DISK-$($vol.DriveLetter)" "Disk" "Critical" "Volume has critically low free space" "$($vol.DriveLetter): has $freePct% free." "Run DEEP_SCAN and cleanup before updates or repair."
        } elseif ($freePct -lt 12) {
            Add-Finding "NEO-DISK-$($vol.DriveLetter)" "Disk" "High" "Volume free space is low" "$($vol.DriveLetter): has $freePct% free." "Clean junk and move large residual files."
        }
        if ($vol.HealthStatus -and $vol.HealthStatus -notin @("Healthy", "Unknown")) {
            Add-Finding "NEO-DISK-HEALTH-$($vol.DriveLetter)" "Disk" "High" "Volume health is not healthy" "$($vol.DriveLetter): $($vol.HealthStatus)." "Back up data and inspect storage health."
        }
    }

    $physical = @()
    try {
        $physical = @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus, Size)
        foreach ($disk in $physical) {
            if ($disk.HealthStatus -and $disk.HealthStatus -ne "Healthy") {
                Add-Finding "NEO-PDISK-$($disk.FriendlyName)" "Disk" "Critical" "Physical disk health warning" "$($disk.FriendlyName): $($disk.HealthStatus), $($disk.OperationalStatus)." "Back up immediately and run vendor diagnostics."
            }
        }
    } catch {}

    return [PSCustomObject]@{ volumes = @($volumes); physical_disks = @($physical) }
}

function Invoke-ImageMaintenance {
    Out-Step "Windows image maintenance"
    $image = [PSCustomObject]@{ dism_check = ""; dism_restore = ""; sfc = "" }

    try {
        $image.dism_check = (& dism.exe /Online /Cleanup-Image /CheckHealth 2>&1) -join "`n"
        if ($image.dism_check -match "repairable|corruption|corrupt|diperbaiki") {
            Add-Finding "NEO-IMG-001" "WindowsImage" "High" "Windows component store reports corruption" "DISM CheckHealth indicates repairable corruption." "Run DISM RestoreHealth."
        }
    } catch {
        Add-Finding "NEO-IMG-002" "WindowsImage" "Medium" "DISM CheckHealth failed" $_.Exception.Message "Run elevated diagnostics."
    }

    if ($Mode -in @("Repair", "Full")) {
        try {
            $image.dism_restore = (& dism.exe /Online /Cleanup-Image /RestoreHealth 2>&1) -join "`n"
            Add-Action "DISM RestoreHealth" "completed" "DISM RestoreHealth completed. Review report output."
        } catch {
            Add-Action "DISM RestoreHealth" "failed" $_.Exception.Message
        }
        try {
            $image.sfc = (& sfc.exe /scannow 2>&1) -join "`n"
            Add-Action "SFC ScanNow" "completed" "SFC scan completed. Review report output."
        } catch {
            Add-Action "SFC ScanNow" "failed" $_.Exception.Message
        }
    } else {
        try {
            $image.sfc = (& sfc.exe /verifyonly 2>&1) -join "`n"
            if ($image.sfc -match "found integrity violations|violations") {
                Add-Finding "NEO-SFC-001" "WindowsImage" "High" "SFC found integrity violations" "sfc /verifyonly reported integrity issues." "Run SYSTEM_REPAIR during a maintenance window."
            }
        } catch {}
    }

    return $image
}

function Invoke-WindowsUpdateReset {
    if ($Mode -notin @("Repair", "Full")) { return }
    Out-Step "Windows Update component reset"
    $services = @("wuauserv", "bits", "cryptsvc", "msiserver")
    foreach ($svc in $services) { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue }
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    try {
        if (Test-Path "$env:WINDIR\SoftwareDistribution") {
            Rename-Item "$env:WINDIR\SoftwareDistribution" "SoftwareDistribution.neo-$stamp" -ErrorAction SilentlyContinue
        }
        if (Test-Path "$env:WINDIR\System32\catroot2") {
            Rename-Item "$env:WINDIR\System32\catroot2" "catroot2.neo-$stamp" -ErrorAction SilentlyContinue
        }
        Add-Action "Windows Update reset" "completed" "SoftwareDistribution/catroot2 renamed for rebuild."
    } catch {
        Add-Action "Windows Update reset" "failed" $_.Exception.Message
    }
    foreach ($svc in $services) { Start-Service -Name $svc -ErrorAction SilentlyContinue }
}

$isAdmin = Test-Admin
if (-not $isAdmin) {
    Add-Finding "NEO-PRIV-001" "Runtime" "Medium" "Diagnostics are not elevated" "Some driver, DISM, service, and WinRE checks may be incomplete." "Run as administrator for full maintenance."
}

$rebootReasons = @(Test-RebootPending)
if ($rebootReasons.Count -gt 0) {
    Add-Finding "NEO-BOOT-REBOOT" "Boot" "Medium" "Pending reboot detected" ($rebootReasons -join ", ") "Reboot during a maintenance window before deeper repairs."
}

$winre = Invoke-WinReCheck
$boot = Invoke-BootAudit
$drivers = Invoke-DriverAudit
$events = Invoke-EventAudit
$services = Invoke-ServiceAudit
$disk = Invoke-DiskAudit
$image = Invoke-ImageMaintenance
Invoke-WindowsUpdateReset

$grade = if ($Script:Score -ge 90) { "A" } elseif ($Script:Score -ge 80) { "B" } elseif ($Script:Score -ge 65) { "C" } elseif ($Script:Score -ge 45) { "D" } else { "F" }

$result = [PSCustomObject]@{
    scan_time = (Get-Date).ToString("o")
    mode = $Mode
    event_days = $EventDays
    elevated = [bool]$isAdmin
    score = [int]$Script:Score
    grade = $grade
    findings = @($Script:Findings)
    actions = @($Script:Actions)
    reboot_pending = @($rebootReasons)
    winre = $winre
    boot = $boot
    drivers = $drivers
    events = $events
    services = @($services)
    disk = $disk
    windows_image = $image
    report_path = $reportPath
}

$json = $result | ConvertTo-Json -Depth 8
$json | Set-Content -Path $reportPath -Encoding UTF8

Out-Step "Summary"
if ($Script:Score -ge 80) { Out-OK "System score: $($Script:Score)/100 ($grade)" } else { Out-Warn "System score: $($Script:Score)/100 ($grade)" }
Out-Info ("Findings: {0}, Actions: {1}" -f $Script:Findings.Count, $Script:Actions.Count)
Out-Info "Report: $reportPath"

$result | ConvertTo-Json -Depth 8 -Compress | Write-Output
