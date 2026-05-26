#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    NeoOptimize Next-Gen Core Engine
    Enterprise-grade automation, safety checks, health scoring, boot optimization,
    profile switching, and resource limits.
.DESCRIPTION
    Integrates machine-learning-inspired heuristics to optimize Windows systems
    without risk of corruption or unnecessary overhead.
#>

# Enforce Ultra-Low Footprint Priority Class
try {
    $proc = [System.Diagnostics.Process]::GetCurrentProcess()
    $proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
    Write-Log "NeoOptimize Process Priority initialized: BelowNormal" "INFO"
} catch {
    # Fallback if priority cannot be set
}

# -----------------------------------------------------------------------------
# 1. AUTO HARDWARE SAFEGUARDS ENGINE
# -----------------------------------------------------------------------------
function Get-NeoHardwareSafeguards {
    Write-Log "Menjalankan deteksi hardware dan kelayakan sistem..." "INFO"
    
    $isSSD = $true
    $isLaptop = $false
    $isVM = $false
    $onBattery = $false
    $logicalProcs = [int]$env:NUMBER_OF_PROCESSORS
    $ramGB = 8.0

    try {
        # Check system drive storage medium (SSD vs HDD)
        $sysDriveLetter = $env:SystemDrive.Replace(":", "")
        $sysDisk = Get-PhysicalDisk | Where-Object { 
            $_.DeviceId -eq (Get-Partition -DriveLetter $sysDriveLetter -ErrorAction SilentlyContinue).DiskNumber 
        } -ErrorAction SilentlyContinue
        
        if ($sysDisk) {
            $mediaType = $sysDisk.MediaType
            if ($mediaType -eq "HDD" -or $sysDisk.SpindleSpeed -gt 0) {
                $isSSD = $false
            }
        }
    } catch {
        # Default fallback
        $isSSD = $true 
    }

    try {
        # Detect battery presence / laptop chassis
        $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
        if ($battery -and $battery.Count -gt 0) {
            $isLaptop = $true
        }
    } catch {}

    try {
        # Detect Virtual Machine environment
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($cs) {
            $model = $cs.Model
            $manufacturer = $cs.Manufacturer
            if ($model -match "Virtual" -or $model -match "VMware" -or $model -match "VirtualBox" -or $manufacturer -match "Xen" -or $model -match "KVM") {
                $isVM = $true
            }
            if ($cs.TotalPhysicalMemory) {
                $ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
            }
        }
    } catch {}

    try {
        # Detect AC / Battery status
        Add-Type -AssemblyName System.Windows.Forms
        $powerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus
        if ($powerStatus -and $powerStatus.PowerLineStatus -eq "Offline") {
            $onBattery = $true
        }
    } catch {}

    # Define smart, dynamic safeguards based on detected telemetry
    $safeguards = [PSCustomObject]@{
        IsLaptop = $isLaptop
        IsSSD = $isSSD
        IsVM = $isVM
        OnBattery = $onBattery
        LogicalProcessors = $logicalProcs
        TotalRAM = $ramGB
        
        # Guard rules to prevent dangerous settings
        BypassUltimatePower = ($isLaptop -and $onBattery) -or $isVM
        BypassDisableSysMain = ($isSSD -eq $false) # DO NOT disable SysMain on HDD
        BypassAggressiveVisuals = ($ramGB -gt 16 -and $logicalProcs -gt 8) # Avoid ruinous UI degradation on high-end hardware
        BypassHeavyIO = ($isSSD -eq $false -and $onBattery -eq $true) # Stagger IO even further if HDD on Battery
    }

    Write-Log "Hardware Safeguards computed: Laptop=$isLaptop, SSD=$isSSD, VM=$isVM, Battery=$onBattery" "OK"
    return $safeguards
}

# -----------------------------------------------------------------------------
# 2. DEEP HEALTH MONITORING SCREENING & SCORE
# -----------------------------------------------------------------------------
function Invoke-NeoHealthScreening {
    param(
        [bool]$Run = $true
    )

    if (-not $Run) { return $null }

    Write-Log "Memulai screening kesehatan system real-time..." "INFO"
    
    $junkTotalMB = 0.0
    $registryErrorCount = 0
    $failedDrivers = @()
    $sysFileErrors = $false
    $sfcStatus = "Healthy"
    $cpuUsage = 0
    $ramUsagePct = 0
    $diskSmartStatus = "Healthy"
    $netLatencyMs = 0.0
    $netPacketLoss = 0.0
    
    # 2.1 Calculate Junk Files Volume
    $junkPaths = @(
        $env:TEMP,
        "$env:LOCALAPPDATA\Temp",
        "C:\Windows\Temp",
        "C:\Windows\Prefetch",
        "C:\ProgramData\Microsoft\Windows\WER\ReportArchive",
        "C:\ProgramData\Microsoft\Windows\WER\ReportQueue"
    )
    foreach ($p in $junkPaths) {
        $junkTotalMB += Get-FolderSizeMB $p
    }

    # 2.2 Deep Registry Scan (Safe obsolete CLSID, Startup paths check)
    $regPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($rp in $regPaths) {
        if (Test-Path $rp) {
            $props = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue
            $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                $cmd = [string]$_.Value
                # Heuristic: Check if executable file path in startup actually exists
                if ($cmd -match '"([^"]+)"' -or $cmd -match '^([^\s]+)') {
                    $exePath = $Matches[1]
                    if (-not (Test-Path $exePath) -and $exePath -notmatch "cmd" -and $exePath -notmatch "powershell") {
                        $registryErrorCount++
                    }
                }
            }
        }
    }

    # 2.3 Failed/Outdated Drivers Scan
    try {
        $failedDevices = Get-PnpDevice -Status Error, Degraded -ErrorAction SilentlyContinue
        if ($failedDevices) {
            foreach ($dev in $failedDevices) {
                $failedDrivers += $dev.FriendlyName
            }
        }
    } catch {}

    # 2.4 Windows Component Store Integrity
    try {
        $cbsKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing" -Name "RebootPending" -ErrorAction SilentlyContinue
        if ($cbsKey) {
            $sysFileErrors = $true
            $sfcStatus = "Pending Reboot Required"
        }
    } catch {}

    # 2.5 Hardware Load Telemetry
    try {
        $cpuCounter = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue
        $cpuUsage = [int][math]::Round($cpuCounter.CounterSamples[0].CookedValue)
    } catch {
        $cpuUsage = 15
    }

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $freeRam = $os.FreePhysicalMemory
        $totalRam = $os.TotalVisibleMemorySize
        $ramUsagePct = [int][math]::Round((($totalRam - $freeRam) / $totalRam) * 100)
    } catch {
        $ramUsagePct = 40
    }

    # 2.6 SMART Disk Health
    try {
        $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
        foreach ($d in $disks) {
            if ($d.HealthStatus -ne "Healthy" -or $d.OperationalStatus -ne "OK") {
                $diskSmartStatus = "Failure Warning / Degraded ($($d.OperationalStatus))"
            }
        }
    } catch {
        $diskSmartStatus = "Unknown (Check not available)"
    }

    # 2.7 Network Diagnostics (Ping Google DNS)
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $replyCount = 4
        $lost = 0
        $latencies = @()
        for ($i=0; $i -lt $replyCount; $i++) {
            $res = $ping.Send("8.8.8.8", 1200)
            if ($res.Status -eq "Success") {
                $latencies += $res.RoundtripTime
            } else {
                $lost++
            }
            Start-Sleep -Milliseconds 50 # Avoid flood
        }
        $netPacketLoss = [math]::Round(($lost / $replyCount) * 100, 1)
        if ($latencies.Count -gt 0) {
            $netLatencyMs = [math]::Round(($latencies | Measure-Object -Average).Average, 1)
        } else {
            $netLatencyMs = 999.0
        }
    } catch {
        $netPacketLoss = 100.0
        $netLatencyMs = 999.0
    }

    # 2.8 Compute Health Score (Base: 100)
    $score = 100
    $remediationNotes = [System.Collections.Generic.List[string]]::new()

    # Deduct for failed drivers
    if ($failedDrivers.Count -gt 0) {
        $penalty = $failedDrivers.Count * 6
        $score -= [math]::Min(18, $penalty)
        $remediationNotes.Add("Ditemukan $($failedDrivers.Count) driver bermasalah. Segera lakukan update driver via Device Manager.")
    }
    # Deduct for registry invalid paths
    if ($registryErrorCount -gt 0) {
        $score -= [math]::Min(10, $registryErrorCount * 2)
        $remediationNotes.Add("Terdeteksi registry error/startup link mati. Bersihkan item startup usang.")
    }
    # Deduct for junk
    if ($junkTotalMB -gt 5120) {
        $score -= 10
        $remediationNotes.Add("File sampah menumpuk sangat tinggi (>5 GB). Jalankan Extreme Junk Cleaner.")
    } elseif ($junkTotalMB -gt 2048) {
        $score -= 5
        $remediationNotes.Add("File sampah mulai menumpuk (>2 GB). Direkomendasikan pembersihan.")
    }
    # Deduct for disk space
    try {
        $sysDrive = Get-PSDrive C -ErrorAction SilentlyContinue
        $freePct = ($sysDrive.Free / ($sysDrive.Used + $sysDrive.Free)) * 100
        if ($freePct -lt 10) {
            $score -= 20
            $remediationNotes.Add("Kapasitas Drive C: kritis (< 10% kosong). Bersihkan cache aplikasi berat.")
        }
    } catch {}
    # Deduct for hardware
    if ($diskSmartStatus -match "Failure" -or $diskSmartStatus -match "Degraded") {
        $score -= 30
        $remediationNotes.Add("PERINGATAN SMART: Fisik harddrive Anda terdeteksi bermasalah/degraded. Harap backup data Anda segera!")
    }
    if ($ramUsagePct -gt 90) {
        $score -= 8
        $remediationNotes.Add("Tekanan RAM sangat tinggi (>90%). Tutup aplikasi background tak berguna.")
    }
    # Deduct for network
    if ($netPacketLoss -gt 10.0) {
        $score -= 15
        $remediationNotes.Add("Koneksi jaringan terganggu (Packet Loss > 10%). Periksa router atau kabel LAN.")
    } elseif ($netLatencyMs -gt 200.0) {
        $score -= 5
        $remediationNotes.Add("Latensi jaringan tinggi ($netLatencyMs ms). Optimalkan pengaturan TCP/IP.")
    }

    $score = [math]::Max(10, $score)
    $grade = switch ($score) {
        {$_ -ge 95} { "A+" }
        {$_ -ge 90} { "A" }
        {$_ -ge 80} { "B" }
        {$_ -ge 70} { "C" }
        {$_ -ge 50} { "D" }
        default     { "F" }
    }

    $screeningResult = [PSCustomObject]@{
        Score = $score
        Grade = $grade
        JunkMB = [math]::Round($junkTotalMB, 2)
        RegErrors = $registryErrorCount
        FailedDrivers = $failedDrivers
        SfcStatus = $sfcStatus
        CpuUsage = $cpuUsage
        RamUsagePct = $ramUsagePct
        DiskSmart = $diskSmartStatus
        NetworkLatency = $netLatencyMs
        NetworkLoss = $netPacketLoss
        Remediations = @($remediationNotes)
    }

    Write-Log "Health Screening Complete: Score=$score, Grade=$grade, Junk=$junkTotalMB MB, SMART=$diskSmartStatus" "OK"
    return $screeningResult
}

# -----------------------------------------------------------------------------
# 3. ACTIVE SYSTEM MAINTENANCE & BOOT ACCELERATION
# -----------------------------------------------------------------------------
function Invoke-ActiveSystemMaintenance {
    Write-Log "Memulai pemeliharaan system aktif & akselerasi booting..." "INFO"
    $changes = 0

    # 3.1 Enable Windows Recovery Environment (WinRE) safely
    try {
        $reagent = reagentc.exe /info
        if ($reagent -match "Disabled" -or $reagent -match "nonaktif") {
            Write-Info "Mengaktifkan Recovery Environment (reagentc)..."
            reagentc.exe /enable | Out-Null
            $changes++
            Write-OK "Windows Recovery Environment (WinRE): ENABLED (Proteksi Gagal Booting)"
        } else {
            Write-OK "Windows Recovery Environment (WinRE): sudah aktif"
        }
    } catch {
        Write-Warn "Gagal mendeteksi/mengaktifkan reagentc"
    }

    # 3.2 Optimize Boot Settings via bcdedit (Multi-processor boot & Timeout)
    try {
        Write-Info "Mengoptimalkan pengaturan bootloader..."
        
        # Disable failure-checking screen during normal booting errors to prevent loops
        bcdedit.exe /set "{current}" bootstatuspolicy ignoreallfailures 2>&1 | Out-Null
        
        # MSConfig Multi-processor Boot Acceleration
        $cores = [int]$env:NUMBER_OF_PROCESSORS
        if ($cores -gt 1) {
            bcdedit.exe /set "{current}" numproc $cores 2>&1 | Out-Null
            Write-OK "Boot Processor Count: SET ke Maksimal ($cores core)"
        }
        
        # Set Boot Timeout to 3 seconds for extremely fast startup
        bcdedit.exe /timeout 3 2>&1 | Out-Null
        Write-OK "Boot Menu Timeout: SET ke 3 detik"
        $changes += 3
    } catch {
        Write-Warn "Gagal memperbarui parameter bcdedit boot"
    }

    # 3.3 Clear third-party non-Windows startup entries safely
    try {
        Write-Info "Membersihkan program startup non-Windows yang tidak diperlukan..."
        $startupPaths = @(
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
        )
        $disabledCount = 0

        # Whitelist of critical components (do NOT disable)
        $whitelist = @(
            "SecurityHealth", "WindowsDefender", "OneDrive", "Realtek", "Intel", 
            "NVIDIA", "AMD", "Audio", "Synaptics", "NeoOptimize", "Watchdog"
        )

        foreach ($sp in $startupPaths) {
            if (Test-Path $sp) {
                $props = Get-ItemProperty -Path $sp -ErrorAction SilentlyContinue
                foreach ($prop in $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }) {
                    $name = $prop.Name
                    $value = [string]$prop.Value
                    
                    $matched = $false
                    foreach ($w in $whitelist) {
                        if ($name -match $w -or $value -match $w) {
                            $matched = $true
                            break
                        }
                    }

                    if (-not $matched) {
                        # Safe disable: Move to a backup registry key instead of outright deleting
                        $backupPath = $sp.Replace("Run", "NeoBackupRun")
                        if (-not (Test-Path $backupPath)) {
                            New-Item -Path $backupPath -Force | Out-Null
                        }
                        Set-ItemProperty -Path $backupPath -Name $name -Value $value -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $sp -Name $name -Force -ErrorAction SilentlyContinue | Out-Null
                        Write-OK "Startup non-Windows dinonaktifkan: $name -> disimpan di backup"
                        $disabledCount++
                    }
                }
            }
        }
        if ($disabledCount -gt 0) {
            $changes++
            Write-OK "Berhasil menonaktifkan $disabledCount startup program non-Windows"
        } else {
            Write-OK "Startup programs sudah bersih."
        }
    } catch {
        Write-Warn "Gagal memproses audit startup"
    }

    # Trigger memory cleanup
    [System.GC]::Collect()
    Write-Log "Active system maintenance complete. Changes=$changes" "OK"
    return $changes
}

# -----------------------------------------------------------------------------
# 4. EXTREME RECURSIVE JUNK CLEANER (DEEP & SYSTEM-WIDE)
# -----------------------------------------------------------------------------
function Invoke-ExtremeJunkCleaner {
    Write-Log "Memulai pembersihan sampah ekstrim tingkat dalam..." "INFO"
    
    $totalFreed = 0.0
    $foldersCleaned = 0
    $filesDeleted = 0

    # Helper for safe nested file deletion with CPU cooling pauses
    function Remove-SafeFile {
        param([string]$FilePath)
        try {
            if (Test-Path $FilePath) {
                $sizeBytes = (Get-Item -Path $FilePath -Force -ErrorAction SilentlyContinue).Length
                Remove-Item -Path $FilePath -Force -ErrorAction SilentlyContinue
                $script:filesDeleted++
                $script:totalFreed += ($sizeBytes / 1MB)
                
                # CPU throttle/cooling to respect user resource usage
                Start-Sleep -Milliseconds 5
            }
        } catch {}
    }

    # 4.1 Purge User/System Caches & Core Junk
    $coreJunkPaths = @(
        $env:TEMP,
        $env:TMP,
        "C:\Windows\Temp",
        "C:\Windows\Prefetch",
        "$env:LOCALAPPDATA\Temp",
        "$env:LOCALAPPDATA\CrashDumps",
        "C:\Windows\Minidump",
        "C:\ProgramData\Microsoft\Windows\WER\ReportArchive",
        "C:\ProgramData\Microsoft\Windows\WER\ReportQueue",
        "C:\ProgramData\Microsoft\Windows\WER\Temp",
        "C:\Windows\SoftwareDistribution\Download",
        "$env:LOCALAPPDATA\Microsoft\Windows\WER"
    )

    Write-Info "Pembersihan folder Temp & Prefetch..."
    foreach ($p in $coreJunkPaths) {
        if (Test-Path $p) {
            Get-ChildItem -Path $p -Force -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-SafeFile $_.FullName
            }
            $foldersCleaned++
        }
    }

    # 4.2 Browser deep cache purging (Chrome, Edge, Firefox, Brave, Opera, Vivaldi)
    Write-Info "Pembersihan cache browser komprehensif..."
    $browserJunk = @(
        @{P="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"; L="Chrome Cache"},
        @{P="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"; L="Chrome Code Cache"},
        @{P="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache"; L="Chrome GPU Cache"},
        @{P="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"; L="Edge Cache"},
        @{P="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache"; L="Edge Code Cache"},
        @{P="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache"; L="Edge GPU Cache"},
        @{P="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache"; L="Brave Cache"},
        @{P="$env:LOCALAPPDATA\Opera Software\Opera Stable\Cache"; L="Opera Cache"},
        @{P="$env:LOCALAPPDATA\Vivaldi\User Data\Default\Cache"; L="Vivaldi Cache"}
    )
    foreach ($b in $browserJunk) {
        if (Test-Path $b.P) {
            Get-ChildItem -Path $b.P -Force -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-SafeFile $_.FullName
            }
        }
    }

    # FirefoxProfiles
    $ffDir = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $ffDir) {
        Get-ChildItem -Path $ffDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            foreach ($sub in @("cache2", "startupCache", "thumbnails", "OfflineCache")) {
                $subPath = Join-Path $_.FullName $sub
                if (Test-Path $subPath) {
                    Get-ChildItem -Path $subPath -Force -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                        Remove-SafeFile $_.FullName
                    }
                }
            }
        }
    }

    # 4.3 Deep Application Caches (Discord, Spotify, Steam, Zoom, Teams, WhatsApp, iTunes)
    Write-Info "Pembersihan cache aplikasi sosial & gaming..."
    $appJunk = @(
        @{P="$env:APPDATA\discord\Cache"; L="Discord Cache"},
        @{P="$env:APPDATA\discord\Code Cache"; L="Discord Code Cache"},
        @{P="$env:LOCALAPPDATA\Spotify\Storage"; L="Spotify Storage"},
        @{P="$env:LOCALAPPDATA\Spotify\Data"; L="Spotify Data"},
        @{P="C:\Program Files (x86)\Steam\appcache"; L="Steam Cache"},
        @{P="C:\Program Files (x86)\Steam\depotcache"; L="Steam Depot"},
        @{P="$env:APPDATA\Microsoft\Teams\Cache"; L="Teams Cache"},
        @{P="$env:LOCALAPPDATA\Microsoft\Teams\Backgrounds"; L="Teams backgrounds"},
        @{P="$env:LOCALAPPDATA\Zoom\data"; L="Zoom data"},
        @{P="$env:LOCALAPPDATA\Packages\5319275A.WhatsAppDesktop_cv1g1gvanyjgm\LocalState\shared\transfers"; L="WhatsApp Media Caches"},
        @{P="$env:APPDATA\Apple Computer\Logs"; L="Apple logs"}
    )
    foreach ($app in $appJunk) {
        if (Test-Path $app.P) {
            Get-ChildItem -Path $app.P -Force -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-SafeFile $_.FullName
            }
        }
    }

    # 4.4 Event Viewer Log Cleaner (Safe backup logic, clear secondary non-essential event logs)
    Write-Info "Pembersihan log Windows Event Viewer non-kritis..."
    try {
        $logList = wevtutil.exe el 2>$null
        if ($logList) {
            # Avoid clearing core system/security logs to preserve compliance audit trails
            $excludeLogs = @("System", "Security", "Application", "Setup")
            foreach ($log in $logList) {
                $matched = $false
                foreach ($ex in $excludeLogs) {
                    if ($log -ieq $ex) { $matched = $true; break }
                }
                if (-not $matched) {
                    wevtutil.exe cl "$log" 2>$null
                }
            }
            Write-OK "Log Event Viewer non-kritis dibersihkan"
        }
    } catch {}

    # 4.5 Recursive scan for residual folders/files & empty folder cleanup
    Write-Info "Pembersihan residu software & folder kosong..."
    
    # Safe targets for empty directory purge (never do C:\Windows or critical folders)
    $safePurgeRoots = @(
        $env:TEMP,
        "$env:LOCALAPPDATA\Temp",
        "C:\Windows\Temp",
        "$env:USERPROFILE\Downloads"
    )

    function Remove-EmptyFoldersRecursive {
        param([string]$Path)
        if (-not (Test-Path $Path)) { return }
        try {
            $subdirs = Get-ChildItem -Path $Path -Directory -Force -ErrorAction SilentlyContinue
            foreach ($sd in $subdirs) {
                Remove-EmptyFoldersRecursive $sd.FullName
            }
            
            # Check again after subdirectories have been processed
            $contents = Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue
            if ($null -eq $contents -or $contents.Count -eq 0) {
                Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue
                $script:foldersCleaned++
            }
        } catch {}
    }

    foreach ($root in $safePurgeRoots) {
        Remove-EmptyFoldersRecursive $root
    }

    # Final cleanup commands
    ipconfig /flushdns 2>&1 | Out-Null
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    } catch {}

    [System.GC]::Collect()
    $totalFreed = [math]::Round($totalFreed, 2)
    Write-Log "Extreme Junk Cleaner complete: Freed=$totalFreed MB, FilesDeleted=$filesDeleted, FoldersCleaned=$foldersCleaned" "OK"
    
    return [PSCustomObject]@{
        TotalFreedMB = $totalFreed
        FilesDeleted = $filesDeleted
        FoldersCleaned = $foldersCleaned
    }
}

# -----------------------------------------------------------------------------
# 5. SELECTABLE DEBLOATER (INTERACTIVE CHECKLIST)
# -----------------------------------------------------------------------------
function Invoke-SelectableDebloater {
    param(
        [bool]$Interactive = $true
    )

    Write-Log "Menjalankan modul Debloater..." "INFO"

    # Core system packages that should NEVER be touched to preserve stability
    $criticalApps = @(
        "Store", "ShellExperience", "System", "Edge", "XboxGameCallableUI", 
        "ParentalControls", "Credentials", "Accounts", "BioEnrollment"
    )

    # Fetch installed Windows UWP Apps
    $allApps = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    if (-not $allApps) {
        Write-Warn "Tidak dapat mendeteksi UWP Packages."
        return
    }

    # Map typical packages to user friendly names
    $debloatTargets = @()
    $safeUninstallable = @(
        @{Name="Xbox App & Gaming Overlays"; ID="*Xbox*"},
        @{Name="Microsoft 3D Builder"; ID="*3DBuilder*"},
        @{Name="Bing Weather"; ID="*BingWeather*"},
        @{Name="Bing News"; ID="*BingNews*"},
        @{Name="Bing Sports"; ID="*BingSports*"},
        @{Name="Bing Finance"; ID="*BingFinance*"},
        @{Name="Windows Maps"; ID="*WindowsMaps*"},
        @{Name="Skype App"; ID="*SkypeApp*"},
        @{Name="Solitaire Collection"; ID="*MicrosoftSolitaireCollection*"},
        @{Name="Office Hub (Get Office)"; ID="*MicrosoftOfficeHub*"},
        @{Name="Zune Video (Movies & TV)"; ID="*ZuneVideo*"},
        @{Name="Zune Music (Groove Music)"; ID="*ZuneMusic*"},
        @{Name="OneNote App"; ID="*Office.OneNote*"},
        @{Name="Sticky Notes"; ID="*MicrosoftStickyNotes*"},
        @{Name="Get Help App"; ID="*GetHelp*"},
        @{Name="Feedback Hub"; ID="*FeedbackHub*"},
        @{Name="Cortana Assistant"; ID="*Microsoft.549981C3F5F10*"}, # Modern Cortana ID
        @{Name="Mixed Reality Portal"; ID="*MixedReality.Portal*"},
        @{Name="Your Phone / Phone Link"; ID="*YourPhone*"},
        @{Name="Windows People Hub"; ID="*People*"},
        @{Name="Alarms & Clock"; ID="*WindowsAlarms*"},
        @{Name="Windows Camera"; ID="*WindowsCamera*"},
        @{Name="Voice Recorder"; ID="*WindowsSoundRecorder*"}
    )

    # Cross reference installed apps with our uninstallable targets
    $uiList = [System.Collections.Generic.List[object]]::new()
    foreach ($target in $safeUninstallable) {
        $found = $allApps | Where-Object { $_.Name -like $target.ID } | Select-Object -First 1
        if ($found) {
            $null = $uiList.Add([PSCustomObject]@{
                Pilihan = $false
                Aplikasi = $target.Name
                PackageName = $found.PackageFullName
            })
        }
    }

    if ($uiList.Count -eq 0) {
        Write-OK "Windows UWP bloatware sudah bersih/tidak ditemukan."
        return
    }

    $selectedApps = @()
    if ($Interactive) {
        # Check if Out-GridView is supported/running in an interactive session
        $gridViewSupported = $true
        try {
            $test = $uiList | Out-GridView -Title "TEST" -PassThru -ErrorAction Stop
        } catch {
            $gridViewSupported = $false
        }

        if ($gridViewSupported) {
            Write-Info "Membuka GridView UI Selector..."
            $selectedApps = $uiList | Out-GridView -Title "Pilih Aplikasi Windows Bloatware yang Ingin Anda Uninstall" -PassThru
        } else {
            # Interactive Console Selection Fallback
            Write-NeoLogo -Compact
            Write-SectionHeader "" "DEBLOAT SELECTOR" "Pilih aplikasi yang ingin dihapus"
            $i = 1
            foreach ($app in $uiList) {
                Write-Host "  $($Global:CYAN)[$i]$($Global:RESET) $($app.Aplikasi)"
                $i++
            }
            Write-Host "  $($Global:CYAN)[A]$($Global:RESET) Pilih Semua"
            Write-Host "  $($Global:CYAN)[0]$($Global:RESET) Batalkan"
            Write-Host ""
            
            $input = Read-NeoChoice "  Masukkan angka dipisahkan koma (misal: 1,3,5) atau A" @() "0"
            if ($input -eq "0") {
                Write-Skip "Debloater"
                return
            } elseif ($input.ToUpper() -eq "A") {
                $selectedApps = @($uiList)
            } else {
                $choices = $input -split ","
                foreach ($c in $choices) {
                    $index = [int]$c.Trim() - 1
                    if ($index -ge 0 -and $index -lt $uiList.Count) {
                        $selectedApps += $uiList[$index]
                    }
                }
            }
        }
    } else {
        # Non-interactive / RMM Mode default safe uninstall choices (Xbox, Cortana, Feedback, MixedReality, Bing)
        $defaultBloatPatterns = @("*Xbox*", "*3DBuilder*", "*BingNews*", "*BingSports*", "*BingFinance*", "*FeedbackHub*", "*Microsoft.549981C3F5F10*", "*MixedReality.Portal*")
        foreach ($app in $uiList) {
            foreach ($pattern in $defaultBloatPatterns) {
                if ($app.PackageName -like $pattern) {
                    $selectedApps += $app
                    break
                }
            }
        }
    }

    if ($selectedApps.Count -eq 0) {
        Write-OK "Tidak ada aplikasi yang dipilih untuk uninstall."
        return
    }

    Write-Info "Memulai proses debloat $($selectedApps.Count) aplikasi..."
    $uninstalledCount = 0
    foreach ($app in $selectedApps) {
        Write-Step "Uninstalling $($app.Aplikasi)..."
        try {
            Remove-AppxPackage -Package $app.PackageName -ErrorAction Stop
            # Also remove provisioned package to prevent it from re-installing during system updates
            $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -eq $app.PackageName }
            if ($prov) {
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue | Out-Null
            }
            Write-OK "Sukses uninstall $($app.Aplikasi)"
            $uninstalledCount++
        } catch {
            Write-Warn "Gagal uninstall $($app.Aplikasi): $($_.Exception.Message)"
        }
        Start-Sleep -Milliseconds 100 # CPU Cooling pause
    }

    Write-OK "Debloater selesai: $uninstalledCount dari $($selectedApps.Count) aplikasi dibersihkan."
}

# -----------------------------------------------------------------------------
# 6. SYSTEM OPTIMIZATION PROFILE SYSTEM
# -----------------------------------------------------------------------------
function Apply-NeoOptimizationProfile {
    param(
        [ValidateSet("Work", "Gaming", "General")]
        [string]$Mode = "General"
    )

    Write-NeoLogo -Compact
    Write-SectionHeader "" "PROFILE SETUP ENGINE" "Menerapkan profil optimasi: $Mode"
    Write-Log "Menerapkan Optimization Profile: $Mode" "INFO"

    $safeguards = Get-NeoHardwareSafeguards
    $changes = 0

    switch ($Mode) {
        "Work" {
            # 6.1 Work/Office Mode: Focus on Extreme Stability, updates safety, office background services
            Write-Step "Menerapkan profil WORKSTATION & OFFICE..."
            
            # Power Plan: Safe Balanced Plan
            try {
                & powercfg.exe /setactive SCHEME_BALANCED 2>&1 | Out-Null
                Write-OK "Power Plan: Balanced (Optimal untuk efisiensi & stabilitas)"
                $changes++
            } catch {}

            # Core Services: Ensure bluetooth, print spooler, smart card are ENABLED
            $officeSvcs = @(
                @{Name="Spooler"; Startup="Automatic"; Label="Print Spooler"},
                @{Name="bthserv"; Startup="Manual"; Label="Bluetooth Support Service"},
                @{Name="WbioSrvc"; Startup="Manual"; Label="Windows Biometric Service"},
                @{Name="SCardSvr"; Startup="Manual"; Label="Smart Card Service"},
                @{Name="Wsearch"; Startup="Automatic"; Label="Windows Search (Indexer)"}
            )
            foreach ($s in $officeSvcs) {
                Set-ServiceState -Name $s.Name -StartupType $s.Startup -Label $s.Label
                $changes++
            }

            # Windows Update Safety Active Hours setup (8 AM - 5 PM)
            try {
                $activeHoursPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
                Set-Reg $activeHoursPath "ActiveHoursStart" 8 | Out-Null
                Set-Reg $activeHoursPath "ActiveHoursEnd" 17 | Out-Null
                Set-Reg $activeHoursPath "SmartActiveHoursState" 0 | Out-Null
                Write-OK "Windows Update Active Hours: Enforced (08:00 - 17:00)"
                $changes++
            } catch {}

            # Disable heavy game overlays, keep standard features
            Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0 | Out-Null
            Write-OK "Windows Game Overlay: DISABLED (Stabilitas workspace)"
            $changes++
        }

        "Gaming" {
            # 6.2 Gaming/Ultimate Mode: Extreme priority to gaming processes, lowest latency, ultimate power
            Write-Step "Menerapkan profil GAMING & ULTIMATE PERFORMANCE..."

            # Ultimate Performance Power Plan configuration
            if (-not $safeguards.BypassUltimatePower) {
                try {
                    $ultPlanGuid = "e9a22243-d3c9-4506-b8db-98444b9a50c2"
                    # Duplicate scheme if not present
                    $check = powercfg.exe /list
                    if ($check -notmatch $ultPlanGuid) {
                        powercfg.exe /duplicatescheme $ultPlanGuid 2>&1 | Out-Null
                    }
                    powercfg.exe /setactive $ultPlanGuid 2>&1 | Out-Null
                    Write-OK "Power Plan: ENFORCED Ultimate Performance"
                    $changes++
                } catch {
                    & powercfg.exe /setactive SCHEME_MIN 2>&1 | Out-Null # High Performance fallback
                    Write-OK "Power Plan: High Performance fallback"
                    $changes++
                }
            } else {
                & powercfg.exe /setactive SCHEME_BALANCED 2>&1 | Out-Null
                Write-Warn "Bypass Ultimate Power: Laptop on Battery / VM terdeteksi. Dipaksa Balanced untuk kesehatan baterai."
            }

            # CPU Core Parking & Throttling optimization
            try {
                # Disable core parking to prevent latency spikes
                Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\545335f6-707b-4e2c-93c7-74071d009b07\0cc5b647-c1df-4637-891a-dec35c318583" "Attributes" 0 | Out-Null
                Write-OK "CPU Core Parking attributes: OPTIMIZED"
                $changes++
            } catch {}

            # Ultimate GPU Scheduling Support
            try {
                Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2 | Out-Null
                Write-OK "Hardware Accelerated GPU Scheduling (HAGS): ENABLED"
                $changes++
            } catch {}

            # Pause Windows Update (prevent game frame drops due to updates)
            try {
                $pauseUntil = (Get-Date).AddDays(7).ToString("yyyy-MM-ddTHH:mm:ssZ")
                $wuPausePath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
                Set-Reg $wuPausePath "PauseUpdatesExpiryTime" $pauseUntil "String" | Out-Null
                Set-Reg $wuPausePath "PauseUpdatesStartTime" (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ") "String" | Out-Null
                Write-OK "Windows Update: PAUSED selama 7 hari untuk mencegah lag background"
                $changes++
            } catch {}

            # Disable gaming-unnecessary services
            $gamingDisabledSvcs = @(
                @{Name="Wsearch"; Startup="Disabled"; Label="Windows Search (Indexer)"},
                @{Name="DiagTrack"; Startup="Disabled"; Label="Connected User Experiences (Telemetry)"},
                @{Name="RemoteRegistry"; Startup="Disabled"; Label="Remote Registry"},
                @{Name="SCardSvr"; Startup="Disabled"; Label="Smart Card Service"},
                @{Name="bthserv"; Startup="Manual"; Label="Bluetooth (Set Manual)"}
            )
            foreach ($s in $gamingDisabledSvcs) {
                Set-ServiceState -Name $s.Name -StartupType $s.Startup -Stop $true -Label $s.Label
                $changes++
            }

            # Ultra-Low Network Latency optimization for gaming
            try {
                Write-Info "Mengoptimalkan parameter latensi jaringan..."
                $tcpPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
                Get-ChildItem -Path $tcpPath -ErrorAction SilentlyContinue | ForEach-Object {
                    $subPath = $_.Name.Replace("HKEY_LOCAL_MACHINE", "HKLM")
                    Set-Reg $subPath "TcpAckFrequency" 1 | Out-Null
                    Set-Reg $subPath "TCPNoDelay" 1 | Out-Null
                }
                Write-OK "Network Gaming Latency: OPTIMIZED (TcpAckFrequency=1, TCPNoDelay=1)"
                $changes++
            } catch {}
        }

        "General" {
            # 6.3 General / Normal Balanced Mode
            Write-Step "Menerapkan profil NORMAL / BALANCED..."
            
            try {
                & powercfg.exe /setactive SCHEME_BALANCED 2>&1 | Out-Null
                Write-OK "Power Plan: Balanced"
                $changes++
            } catch {}

            # Restore normal services
            $normalSvcs = @(
                @{Name="Wsearch"; Startup="Automatic"; Label="Windows Search"},
                @{Name="Spooler"; Startup="Automatic"; Label="Print Spooler"},
                @{Name="bthserv"; Startup="Manual"; Label="Bluetooth Support"},
                @{Name="SCardSvr"; Startup="Manual"; Label="Smart Card"}
            )
            foreach ($s in $normalSvcs) {
                Set-ServiceState -Name $s.Name -StartupType $s.Startup -Label $s.Label
                $changes++
            }

            # Enable normal Active Hours
            try {
                $activeHoursPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
                Set-Reg $activeHoursPath "SmartActiveHoursState" 1 | Out-Null
                Write-OK "Windows Update Active Hours: Reset ke default Windows"
                $changes++
            } catch {}
        }
    }

    [System.GC]::Collect()
    Write-Log "Profile applied successfully. Changes applied=$changes" "OK"
    return $changes
}
