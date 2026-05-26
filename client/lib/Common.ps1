
<#
.SYNOPSIS
    NeoOptimize Common Library
    Shared functions, UI components, and branding for all modules
#>

if ($Global:NeoOptimizeCommonLoaded) {
    return
}
$Global:NeoOptimizeCommonLoaded = $true
$Global:NeoOptimizeRoot = Split-Path -Parent $PSScriptRoot

# Load Next-Gen Core Engine
$NextGenPath = "$PSScriptRoot\NeoNextGenEngine.ps1"
if (Test-Path $NextGenPath) {
    . $NextGenPath
}


# 
#   ANSI COLOR PALETTE
# 
$Global:ESC      = [char]27
function ansi($c)    { "$($Global:ESC)[${c}m" }

$Global:RESET    = ansi 0
$Global:BOLD     = ansi 1
$Global:DIM      = ansi 2
$Global:ITALIC   = ansi 3
$Global:ULINE    = ansi 4

$Global:BLACK    = ansi 30
$Global:RED      = ansi 91
$Global:GREEN    = ansi 92
$Global:YELLOW   = ansi 93
$Global:BLUE     = ansi 94
$Global:MAGENTA  = ansi 95
$Global:CYAN     = ansi 96
$Global:WHITE    = ansi 97

$Global:BG_BLUE  = ansi 44
$Global:BG_CYAN  = ansi 46
$Global:BG_BLACK = ansi 40

# 
#   BRANDING
# 
$Global:PRODUCT_NAME    = "NeoOptimize"
$Global:PRODUCT_VERSION = "1.0.0"
$Global:PRODUCT_TAGLINE = "Windows Optimizer & Agent"

# 
#   RUNTIME FLAGS
# 
if ($null -eq $Global:NeoOptimizeNonInteractive) { $Global:NeoOptimizeNonInteractive = $false }
if ($null -eq $Global:NeoOptimizeSkipPause)      { $Global:NeoOptimizeSkipPause      = $false }
if ($null -eq $Global:NeoOptimizeAssumeYes)      { $Global:NeoOptimizeAssumeYes      = $false }
if ($null -eq $Global:NeoOptimizeConfirmAll)     { $Global:NeoOptimizeConfirmAll     = $false }
if ($null -eq $Global:NeoOptimizeEnforce)        { $Global:NeoOptimizeEnforce        = $false }

# 
#   LOGGING
# 
$Global:LogDir  = Join-Path $Global:NeoOptimizeRoot "reports"
$Global:LogFile = "$($Global:LogDir)\NeoOptimize_$(Get-Date -f 'yyyyMMdd_HHmmss').log"
$Global:LogBuf  = [System.Collections.Generic.List[string]]::new()
$Global:BackupDir = Join-Path $Global:NeoOptimizeRoot "backup"
$Global:RegBackupDir = Join-Path $Global:BackupDir "registry"
$Global:FileBackupDir = Join-Path $Global:BackupDir "files"
$Global:ServiceBackupFile = Join-Path $Global:BackupDir "ServiceStartup_$(Get-Date -f 'yyyyMMdd_HHmmss').csv"
$Global:NeoOptimizeBackedUpRegKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$Global:NeoOptimizeBackedUpServices = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($dir in @($Global:LogDir, $Global:BackupDir, $Global:RegBackupDir, $Global:FileBackupDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

function Write-Log {
    param($Msg, $Level = "INFO")
    $ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts][$Level] $Msg"
    $Global:LogBuf.Add($entry)
    try {
        if (-not (Test-Path $Global:LogDir)) { New-Item -Path $Global:LogDir -ItemType Directory -Force | Out-Null }
        Add-Content -Path $Global:LogFile -Value $entry -ErrorAction SilentlyContinue
    } catch {}
}

# 
#   PRINT HELPERS
# 
function Write-OK   { param($m) Write-Host "  $($Global:GREEN)$($Global:RESET) $m"; Write-Log $m "OK" }
function Write-Warn { param($m) Write-Host "  $($Global:YELLOW)$($Global:RESET) $m"; Write-Log $m "WARN" }
function Write-Err  { param($m) Write-Host "  $($Global:RED)$($Global:RESET) $m"; Write-Log $m "ERROR" }
function Write-Info { param($m) Write-Host "  $($Global:CYAN)$($Global:RESET) $m"; Write-Log $m "INFO" }
function Write-Skip { param($m) Write-Host "  $($Global:DIM) $m (skipped)$($Global:RESET)" }
function Write-Step { param($m) Write-Host "  $($Global:MAGENTA)$($Global:RESET) $($Global:BOLD)$m$($Global:RESET)" }

function Write-Separator {
    param($Char = "", $Color = $Global:DIM)
    Write-Host "$Color$($Char * 68)$($Global:RESET)"
}

function Write-SectionHeader {
    param($Icon, $Title, $Subtitle = "")
    Write-Host ""
    Write-Host "$($Global:CYAN)$($Global:BOLD)  $($Global:RESET)"
    Write-Host "$($Global:CYAN)$($Global:BOLD)    $Icon $($Title.PadRight(63))$($Global:RESET)"
    if ($Subtitle) {
        Write-Host "$($Global:DIM)    $($Subtitle.PadRight(65))$($Global:RESET)"
    }
    Write-Host "$($Global:CYAN)$($Global:BOLD)  $($Global:RESET)"
    Write-Host ""
}

function Write-ModuleHeader {
    param($Number, $Icon, $Title)
    Clear-Host
    Write-NeoLogo -Compact
    Write-Host ""
    Write-Host "  $($Global:BG_BLUE)$($Global:WHITE)$($Global:BOLD)  MODULE $Number  $Icon $Title  $($Global:RESET)"
    Write-Host ""
}

function Show-Progress {
    param($Current, $Total, $Label = "")
    $pct  = [math]::Round(($Current / $Total) * 100)
    $fill = [math]::Round(($Current / $Total) * 40)
    $bar  = "" * $fill + "" * (40 - $fill)
    Write-Host -NoNewline "`r  $($Global:CYAN)[$bar]$($Global:RESET) $pct%  $($Global:DIM)$Label$($Global:RESET)    "
    if ($Current -eq $Total) { Write-Host "" }
}

function Wait-AnyKey {
    param($Msg = "Tekan tombol apapun untuk kembali ke menu...")
    if ($Global:NeoOptimizeSkipPause -or $Global:NeoOptimizeNonInteractive) { return }
    Write-Host ""
    Write-Host "  $($Global:DIM)$Msg$($Global:RESET)"
    try {
        if ([System.Console]::IsInputRedirected) { return }
        [void][System.Console]::ReadKey($true)
    } catch {
        Start-Sleep -Seconds 1
    }
}

function Read-NeoChoice {
    param(
        [string]$Prompt,
        [string[]]$Valid,
        [string]$Default = ""
    )

    if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) {
        if ($Default) { Write-Info "Non-interactive: memakai default '$Default' untuk $Prompt" }
        return $Default
    }

    while ($true) {
        $suffix = if ($Default) { " [default: $Default]" } else { "" }
        $value = (Read-Host "$Prompt$suffix").Trim()
        if (-not $value -and $Default) { return $Default }
        if ($Valid.Count -eq 0 -or $Valid -contains $value) { return $value }
        Write-Warn "Pilihan tidak valid: '$value'"
    }
}

function Confirm-NeoAction {
    param(
        [string]$Prompt,
        [bool]$Default = $false
    )

    if ($Global:NeoOptimizeConfirmAll) { return $true }
    if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) { return $Default }

    $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }
    $answer = (Read-Host "$Prompt $suffix").Trim()
    if (-not $answer) { return $Default }
    return $answer -in @("y", "Y", "yes", "YES", "Ya", "ya")
}

function Test-NeoHighRiskConsent {
    param(
        [string]$ActionName,
        [string]$RiskLevel = "High",
        [string]$Reason = "Aksi ini dapat mengubah registry, service, firewall, boot, atau konfigurasi sistem."
    )

    if ($RiskLevel -notin @("High", "Critical")) { return $true }
    if ($Global:NeoOptimizeEnforce) { return $true }

    Write-Warn "$ActionName adalah aksi $RiskLevel."
    if ($Reason) { Write-Info $Reason }
    Write-Info "Default NeoOptimize sekarang audit-first agar tidak memicu perubahan sistem agresif tanpa persetujuan."

    if ($Global:NeoOptimizeNonInteractive -or $Global:NeoOptimizeAssumeYes -or [System.Console]::IsInputRedirected) {
        Write-Warn "Diblokir: mode otomatis/non-interaktif tidak boleh menjalankan aksi high-risk tanpa parameter -Enforce."
        Write-Info "Jalankan AI Doctor/Agent Audit dulu, lalu ulangi dengan -Enforce jika benar-benar ingin menerapkan perubahan."
        return $false
    }

    $answer = (Read-Host "  Ketik ENFORCE untuk menerapkan perubahan high-risk, atau Enter untuk batal").Trim()
    if ($answer -eq "ENFORCE") {
        $Global:NeoOptimizeEnforce = $true
        Write-Warn "Mode enforce aktif untuk sesi ini."
        return $true
    }

    Write-Info "Aksi dibatalkan. Tidak ada perubahan high-risk diterapkan."
    return $false
}

function ConvertTo-HtmlSafe {
    param($Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

# 
#   REGISTRY HELPER
# 
function ConvertTo-RegExePath {
    param([string]$Path)
    if ($Path -match '^HKLM:\\(.+)$') { return "HKLM\$($Matches[1])" }
    if ($Path -match '^HKCU:\\(.+)$') { return "HKCU\$($Matches[1])" }
    if ($Path -match '^HKCR:\\(.+)$') { return "HKCR\$($Matches[1])" }
    if ($Path -match '^HKU:\\(.+)$')  { return "HKU\$($Matches[1])" }
    if ($Path -match '^HKCC:\\(.+)$') { return "HKCC\$($Matches[1])" }
    return $Path
}

function Backup-RegKey {
    param([string]$Path)
    if (-not $Path) { return $false }
    if ($Global:NeoOptimizeBackedUpRegKeys.Contains($Path)) { return $true }

    $null = $Global:NeoOptimizeBackedUpRegKeys.Add($Path)
    $native = ConvertTo-RegExePath $Path
    $safeName = ($native -replace '[\\/:*?"<>| ]+', '_').Trim('_')
    $out = Join-Path $Global:RegBackupDir "$safeName.reg"

    try {
        $result = & reg.exe export $native $out /y 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Registry backup: $native -> $out" "INFO"
            return $true
        }
        Write-Log "Registry backup skipped: $native ($result)" "WARN"
        return $false
    } catch {
        Write-Log "Registry backup failed: $native - $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Set-Reg {
    param($Path, $Name, $Value, $Type = "DWord")
    try {
        Backup-RegKey $Path | Out-Null
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        Write-Log "RegSet: $Path\$Name = $Value ($Type)" "OK"
        return $true
    } catch {
        Write-Log "RegSet failed: $Path\$Name - $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Get-RegValue {
    param($Path, $Name, $Default = $null)
    try {
        return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    } catch {
        return $Default
    }
}

# 
#   SYSTEM SNAPSHOT
# 
function Get-SystemSnapshot {
    $os  = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor
    $cs  = Get-CimInstance Win32_ComputerSystem
    $gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
    $bios= Get-CimInstance Win32_BIOS

    return [PSCustomObject]@{
        Timestamp    = Get-Date
        ComputerName = $env:COMPUTERNAME
        User         = $env:USERNAME
        OS           = $os.Caption
        OSBuild      = "$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild).$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR)"
        CPU          = $cpu.Name
        CPUCores     = $cpu.NumberOfCores
        CPUThreads   = $cpu.NumberOfLogicalProcessors
        RAMTotal     = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
        RAMFree      = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        GPU          = $gpu.Name
        Uptime       = (Get-Date) - $os.LastBootUpTime
        BIOSVersion  = $bios.SMBIOSBIOSVersion
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
    }
}

# 
#   RESTORE POINT
# 
function New-RestorePoint {
    param($Description = "NeoOptimize Backup")
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-OK "System Restore Point: '$Description'"
        Write-Log "Restore Point created: $Description" "INFO"
        return $true
    } catch {
        Write-Warn "Restore Point gagal dibuat: $($_.Exception.Message)"
        return $false
    }
}

#
#   LOCAL SAFETY TRANSACTION + BENCHMARKING
#
function Get-NeoProgramDataRoot {
    if ($env:ProgramData) {
        return (Join-Path $env:ProgramData "NeoOptimize")
    }
    return (Join-Path $Global:NeoOptimizeRoot "reports\programdata")
}

function Initialize-NeoLocalSafetyStore {
    $root = Join-Path (Get-NeoProgramDataRoot) "LocalSafety"
    $dirs = @(
        $root,
        (Join-Path $root "transactions"),
        (Join-Path $Global:LogDir "benchmarks")
    )
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
    return $root
}

function Get-NeoSafeFileName {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "item" }
    return (($Value -replace '[\\/:*?"<>| ]+', '_').Trim('_'))
}

function Get-NeoCounterValue {
    param([string]$CounterPath)
    try {
        $sample = Get-Counter -Counter $CounterPath -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop
        return [math]::Round([double]$sample.CounterSamples[0].CookedValue, 2)
    } catch {
        return $null
    }
}

function Get-NeoBenchmarkSnapshot {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
    $def = Get-MpComputerStatus -ErrorAction SilentlyContinue
    $fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue

    $ramTotalGb = if ($cs.TotalPhysicalMemory) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 2) } else { 0 }
    $ramFreeGb = if ($os.FreePhysicalMemory) { [math]::Round($os.FreePhysicalMemory / 1MB, 2) } else { 0 }
    $ramUsedPct = if ($ramTotalGb -gt 0) { [math]::Round((($ramTotalGb - $ramFreeGb) / $ramTotalGb) * 100, 2) } else { $null }
    $diskFreeGb = if ($disk.FreeSpace) { [math]::Round($disk.FreeSpace / 1GB, 2) } else { $null }
    $diskSizeGb = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 2) } else { $null }
    $diskFreePct = if ($diskSizeGb -and $diskSizeGb -gt 0) { [math]::Round(($diskFreeGb / $diskSizeGb) * 100, 2) } else { $null }
    $uptimeHours = if ($os.LastBootUpTime) { [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 2) } else { $null }

    $stoppedAuto = 0
    try {
        $stoppedAuto = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.StartMode -eq "Auto" -and $_.State -ne "Running" }).Count
    } catch {}

    $healthScore = 100
    if ($diskFreePct -ne $null -and $diskFreePct -lt 10) { $healthScore -= 25 }
    elseif ($diskFreePct -ne $null -and $diskFreePct -lt 18) { $healthScore -= 12 }
    if ($ramUsedPct -ne $null -and $ramUsedPct -gt 90) { $healthScore -= 18 }
    elseif ($ramUsedPct -ne $null -and $ramUsedPct -gt 80) { $healthScore -= 8 }
    if ($stoppedAuto -gt 8) { $healthScore -= 10 }
    if ($def -and $def.RealTimeProtectionEnabled -eq $false) { $healthScore -= 20 }
    if (@($fw | Where-Object { -not $_.Enabled }).Count -gt 0) { $healthScore -= 10 }
    if ($uptimeHours -ne $null -and $uptimeHours -gt 336) { $healthScore -= 5 }
    if ($healthScore -lt 0) { $healthScore = 0 }

    return [PSCustomObject]@{
        timestamp = (Get-Date).ToString("s")
        computer_name = $env:COMPUTERNAME
        os = if ($os) { $os.Caption } else { "" }
        build = if ($os) { $os.BuildNumber } else { "" }
        cpu = if ($cpu) { $cpu.Name } else { "" }
        gpu = if ($gpu) { $gpu.Name } else { "" }
        cpu_usage_pct = Get-NeoCounterValue "\Processor(_Total)\% Processor Time"
        ram_total_gb = $ramTotalGb
        ram_free_gb = $ramFreeGb
        ram_used_pct = $ramUsedPct
        disk_c_size_gb = $diskSizeGb
        disk_c_free_gb = $diskFreeGb
        disk_c_free_pct = $diskFreePct
        disk_queue_length = Get-NeoCounterValue "\PhysicalDisk(_Total)\Avg. Disk Queue Length"
        net_bytes_total_per_sec = Get-NeoCounterValue "\Network Interface(*)\Bytes Total/sec"
        process_count = @(Get-Process -ErrorAction SilentlyContinue).Count
        stopped_auto_services = $stoppedAuto
        defender_realtime = if ($def) { $def.RealTimeProtectionEnabled } else { $null }
        firewall_disabled_profiles = @($fw | Where-Object { -not $_.Enabled } | ForEach-Object { $_.Name })
        uptime_hours = $uptimeHours
        local_health_score = [int]$healthScore
    }
}

function Compare-NeoBenchmarkSnapshot {
    param($Before, $After)
    if (-not $Before -or -not $After) { return $null }
    return [PSCustomObject]@{
        health_score_delta = ([int]$After.local_health_score - [int]$Before.local_health_score)
        ram_free_gb_delta = if ($Before.ram_free_gb -ne $null -and $After.ram_free_gb -ne $null) { [math]::Round([double]$After.ram_free_gb - [double]$Before.ram_free_gb, 2) } else { $null }
        ram_used_pct_delta = if ($Before.ram_used_pct -ne $null -and $After.ram_used_pct -ne $null) { [math]::Round([double]$After.ram_used_pct - [double]$Before.ram_used_pct, 2) } else { $null }
        disk_free_gb_delta = if ($Before.disk_c_free_gb -ne $null -and $After.disk_c_free_gb -ne $null) { [math]::Round([double]$After.disk_c_free_gb - [double]$Before.disk_c_free_gb, 2) } else { $null }
        stopped_auto_services_delta = ([int]$After.stopped_auto_services - [int]$Before.stopped_auto_services)
        process_count_delta = ([int]$After.process_count - [int]$Before.process_count)
    }
}

function Export-NeoRegistrySnapshot {
    param(
        [string]$RegistryPath,
        [string]$OutputDir
    )
    $native = ConvertTo-RegExePath $RegistryPath
    $safeName = Get-NeoSafeFileName $native
    $regFile = Join-Path $OutputDir "$safeName.reg"
    $metaFile = Join-Path $OutputDir "$safeName.json"
    $exists = $false

    try {
        $psPath = $RegistryPath
        if ($RegistryPath -match '^HKLM\\(.+)$') { $psPath = "HKLM:\$($Matches[1])" }
        elseif ($RegistryPath -match '^HKCU\\(.+)$') { $psPath = "HKCU:\$($Matches[1])" }
        elseif ($RegistryPath -match '^HKCR\\(.+)$') { $psPath = "HKCR:\$($Matches[1])" }
        elseif ($RegistryPath -match '^HKU\\(.+)$') { $psPath = "HKU:\$($Matches[1])" }
        elseif ($RegistryPath -match '^HKCC\\(.+)$') { $psPath = "HKCC:\$($Matches[1])" }
        $exists = Test-Path $psPath
    } catch {}

    $result = [ordered]@{
        path = $RegistryPath
        native_path = $native
        existed = [bool]$exists
        file = $regFile
        exported = $false
        error = ""
    }

    if ($exists) {
        try {
            $output = & reg.exe export $native $regFile /y 2>&1
            if ($LASTEXITCODE -eq 0) {
                $result.exported = $true
            } else {
                $result.error = [string]$output
            }
        } catch {
            $result.error = $_.Exception.Message
        }
    }

    $result | ConvertTo-Json -Depth 5 | Set-Content -Path $metaFile -Encoding UTF8 -ErrorAction SilentlyContinue
    return [PSCustomObject]$result
}

function New-NeoLocalSafetyTransaction {
    param(
        [string]$ActionName,
        [string]$RiskLevel = "Medium",
        [string[]]$RegistryKeys = @(),
        [string[]]$ServiceNames = @()
    )

    $store = Initialize-NeoLocalSafetyStore
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $id = "local_$($ActionName)_$stamp"
    $txDir = Join-Path (Join-Path $store "transactions") $id
    $regDir = Join-Path $txDir "registry"
    New-Item -Path $regDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    $tx = [PSCustomObject]@{
        id = $id
        action = $ActionName
        risk_level = $RiskLevel
        status = "PRE_FLIGHT"
        started_at = (Get-Date).ToString("s")
        completed_at = ""
        rolled_back_at = ""
        path = $txDir
        registry_snapshots = @()
        service_snapshot = ""
        restore_point_created = $false
        baseline = Get-NeoBenchmarkSnapshot
        post = $null
        delta = $null
        error = ""
    }

    foreach ($key in @($RegistryKeys | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)) {
        $tx.registry_snapshots += Export-NeoRegistrySnapshot -RegistryPath $key -OutputDir $regDir
    }

    if ($ServiceNames -and $ServiceNames.Count -gt 0) {
        $svcPath = Join-Path $txDir "services.csv"
        foreach ($name in @($ServiceNames | Sort-Object -Unique)) {
            $svc = Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
            if ($svc) {
                [PSCustomObject]@{
                    Name = $svc.Name
                    DisplayName = $svc.DisplayName
                    StartMode = $svc.StartMode
                    State = $svc.State
                } | Export-Csv -Path $svcPath -NoTypeInformation -Append -Encoding UTF8 -ErrorAction SilentlyContinue
            }
        }
        if (Test-Path $svcPath) { $tx.service_snapshot = $svcPath }
    }

    if ($RiskLevel -in @("High", "Critical")) {
        $tx.restore_point_created = [bool](New-RestorePoint "NeoOptimize $ActionName - $stamp")
    }

    $tx.status = "EXECUTING"
    $tx | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $txDir "transaction.json") -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Info "Local safety transaction: $id"
    return $tx
}

function Restore-NeoLocalSafetyTransaction {
    param([string]$TransactionPath)
    $manifestPath = Join-Path $TransactionPath "transaction.json"
    if (-not (Test-Path $manifestPath)) {
        Write-Warn "Rollback gagal: transaction.json tidak ditemukan."
        return $false
    }

    $tx = Get-Content -Path $manifestPath -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
    $restored = 0

    foreach ($snap in @($tx.registry_snapshots)) {
        try {
            if ($snap.existed -and (Test-Path ([string]$snap.file))) {
                & reg.exe import ([string]$snap.file) 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { $restored++ }
            } elseif (-not $snap.existed -and $snap.native_path) {
                & reg.exe delete ([string]$snap.native_path) /f 2>&1 | Out-Null
                $restored++
            }
        } catch {
            Write-Log "Rollback registry failed for $($snap.native_path): $($_.Exception.Message)" "WARN"
        }
    }

    if ($tx.service_snapshot -and (Test-Path ([string]$tx.service_snapshot))) {
        $map = @{ "Auto" = "Automatic"; "Automatic" = "Automatic"; "Manual" = "Manual"; "Disabled" = "Disabled" }
        Import-Csv -Path ([string]$tx.service_snapshot) -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $startup = $map[$_.StartMode]
                if ($startup) { Set-Service -Name $_.Name -StartupType $startup -ErrorAction SilentlyContinue }
                if ($_.State -eq "Running") { Start-Service -Name $_.Name -ErrorAction SilentlyContinue }
                elseif ($_.State -eq "Stopped") { Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue }
            } catch {
                Write-Log "Rollback service failed for $($_.Name): $($_.Exception.Message)" "WARN"
            }
        }
    }

    try {
        $tx.status = "ROLLED_BACK"
        $tx.rolled_back_at = (Get-Date).ToString("s")
        $tx | ConvertTo-Json -Depth 8 | Set-Content -Path $manifestPath -Encoding UTF8
    } catch {}

    Write-OK "Local rollback selesai untuk $($tx.action) ($restored registry snapshot)."
    return $true
}

function Complete-NeoLocalSafetyTransaction {
    param(
        $Transaction,
        [string]$Status = "SUCCESS",
        [string]$ErrorMessage = ""
    )

    if (-not $Transaction -or -not $Transaction.path) { return $null }
    $tx = $Transaction
    $tx.status = $Status
    $tx.completed_at = (Get-Date).ToString("s")
    $tx.error = $ErrorMessage
    $tx.post = Get-NeoBenchmarkSnapshot
    $tx.delta = Compare-NeoBenchmarkSnapshot -Before $tx.baseline -After $tx.post

    $manifestPath = Join-Path $tx.path "transaction.json"
    $benchmarkDir = Join-Path $Global:LogDir "benchmarks"
    if (-not (Test-Path $benchmarkDir)) { New-Item -Path $benchmarkDir -ItemType Directory -Force | Out-Null }
    $benchmarkPath = Join-Path $benchmarkDir "$($tx.id).json"

    $tx | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -Encoding UTF8 -ErrorAction SilentlyContinue
    $tx | ConvertTo-Json -Depth 10 | Set-Content -Path $benchmarkPath -Encoding UTF8 -ErrorAction SilentlyContinue
    Copy-Item -Path $benchmarkPath -Destination (Join-Path $benchmarkDir "latest.json") -Force -ErrorAction SilentlyContinue

    Write-OK "Benchmark before/after: $benchmarkPath"
    return $tx
}

function Invoke-NeoSafetyWrappedAction {
    param(
        [string]$ActionName,
        [string]$RiskLevel = "Medium",
        [string[]]$RegistryKeys = @(),
        [string[]]$ServiceNames = @(),
        [scriptblock]$ScriptBlock
    )

    if (-not (Test-NeoHighRiskConsent -ActionName $ActionName -RiskLevel $RiskLevel)) {
        return
    }

    $tx = New-NeoLocalSafetyTransaction -ActionName $ActionName -RiskLevel $RiskLevel -RegistryKeys $RegistryKeys -ServiceNames $ServiceNames
    try {
        & $ScriptBlock
        Complete-NeoLocalSafetyTransaction -Transaction $tx -Status "SUCCESS" | Out-Null
    } catch {
        $message = $_.Exception.Message
        Complete-NeoLocalSafetyTransaction -Transaction $tx -Status "FAILED" -ErrorMessage $message | Out-Null
        Write-Warn "Aksi $ActionName gagal: $message"
        if ($RiskLevel -in @("High", "Critical")) {
            Write-Warn "Menjalankan rollback lokal karena aksi berisiko gagal."
            Restore-NeoLocalSafetyTransaction -TransactionPath $tx.path | Out-Null
        }
        throw
    }
}

function Invoke-NeoLastLocalRollback {
    $store = Initialize-NeoLocalSafetyStore
    $txRoot = Join-Path $store "transactions"
    $latest = Get-ChildItem -Path $txRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) {
        Write-Warn "Belum ada local safety transaction untuk di-rollback."
        return $false
    }
    Write-Warn "Rollback transaksi terakhir: $($latest.Name)"
    return Restore-NeoLocalSafetyTransaction -TransactionPath $latest.FullName
}

# 
#   FOLDER SIZE HELPER
# 
function Get-FolderSizeMB {
    param($Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        return [math]::Round($size / 1MB, 2)
    } catch { return 0 }
}

function Backup-File {
    param(
        [string]$Path,
        [string]$Label = ""
    )
    if (-not (Test-Path $Path)) { return $false }
    $name = if ($Label) { $Label } else { Split-Path -Leaf $Path }
    $safe = ($name -replace '[\\/:*?"<>| ]+', '_').Trim('_')
    $dest = Join-Path $Global:FileBackupDir "$safe`_$(Get-Date -f 'yyyyMMdd_HHmmss').bak"
    try {
        Copy-Item -Path $Path -Destination $dest -Force -ErrorAction Stop
        Write-Log "File backup: $Path -> $dest" "INFO"
        return $true
    } catch {
        Write-Log "File backup failed: $Path - $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Add-HostsBlock {
    param(
        [string]$BlockName,
        [string[]]$Domains
    )
    if (-not $env:SystemRoot) { return $false }
    $hostsPath = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
    if (-not (Test-Path $hostsPath)) {
        Write-Warn "Hosts file tidak ditemukan: $hostsPath"
        return $false
    }

    $cleanDomains = $Domains |
        Where-Object { $_ -and $_ -match '^[a-zA-Z0-9.-]+$' } |
        Sort-Object -Unique
    if (-not $cleanDomains -or $cleanDomains.Count -eq 0) { return $false }

    Backup-File $hostsPath "hosts" | Out-Null
    $start = "# NeoOptimize BEGIN $BlockName"
    $end   = "# NeoOptimize END $BlockName"
    $lines = @("", $start) + ($cleanDomains | ForEach-Object { "0.0.0.0 $_" }) + @($end, "")
    $block = $lines -join [Environment]::NewLine

    try {
        $existing = Get-Content $hostsPath -Raw -ErrorAction Stop
        $pattern = "(?s)$([regex]::Escape($start)).*?$([regex]::Escape($end))"
        if ($existing -match [regex]::Escape($start)) {
            $updated = [regex]::Replace($existing, $pattern, $block)
        } else {
            $updated = $existing.TrimEnd() + [Environment]::NewLine + $block
        }
        Set-Content -Path $hostsPath -Value $updated -Encoding ASCII -Force -ErrorAction Stop
        Write-OK "Hosts block '$BlockName' diperbarui ($($cleanDomains.Count) domain)"
        return $true
    } catch {
        Write-Warn "Gagal memperbarui hosts file: $($_.Exception.Message)"
        return $false
    }
}

function Remove-NeoFirewallRule {
    param([string]$DisplayName)
    try {
        $rules = Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue
        if ($rules) {
            $rules | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            Write-Log "Firewall rule removed: $DisplayName" "INFO"
            return $true
        }
    } catch {
        netsh advfirewall firewall delete rule name="$DisplayName" 2>&1 | Out-Null
    }
    return $false
}

# 
#   SERVICE HELPER
# 
function Backup-ServiceState {
    param([string]$Name)
    if (-not $Name) { return $false }
    if ($Global:NeoOptimizeBackedUpServices.Contains($Name)) { return $true }

    $svc = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if (-not $svc) { return $false }

    $null = $Global:NeoOptimizeBackedUpServices.Add($Name)
    [PSCustomObject]@{
        Timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Name        = $svc.Name
        DisplayName = $svc.DisplayName
        StartMode   = $svc.StartMode
        State       = $svc.State
    } | Export-Csv -Path $Global:ServiceBackupFile -NoTypeInformation -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Log "Service backup: $Name ($($svc.StartMode), $($svc.State))" "INFO"
    return $true
}

function Restore-ServiceStartupBackup {
    $latest = Get-ChildItem -Path $Global:BackupDir -Filter "ServiceStartup_*.csv" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) { return $false }

    $map = @{ "Auto" = "Automatic"; "Manual" = "Manual"; "Disabled" = "Disabled" }
    $restored = 0
    Import-Csv -Path $latest.FullName -ErrorAction SilentlyContinue | ForEach-Object {
        $startup = $map[$_.StartMode]
        if ($startup) {
            try {
                Set-Service -Name $_.Name -StartupType $startup -ErrorAction Stop
                $restored++
            } catch {
                Write-Log "Service restore failed: $($_.Name) - $($_.Exception.Message)" "WARN"
            }
        }
    }

    if ($restored -gt 0) {
        Write-OK "Restore service startup dari backup: $($latest.Name) ($restored layanan)"
        return $true
    }
    return $false
}

function Set-ServiceState {
    param($Name, $StartupType, $Stop = $false, $Label = "")
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Skip "$Name"; return }
    $display = if ($Label) { $Label } else { $svc.DisplayName }
    try {
        Backup-ServiceState $Name | Out-Null
        if ($Stop -and $svc.Status -eq "Running") {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        }
        Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
        $icon = switch ($StartupType) {
            "Disabled"  { "$($Global:RED)$($Global:RESET)" }
            "Automatic" { "$($Global:GREEN)$($Global:RESET)" }
            "Manual"    { "$($Global:YELLOW)$($Global:RESET)" }
            default     { "$($Global:DIM)$($Global:RESET)" }
        }
        Write-Host "  $icon [$($StartupType.PadRight(9))] $display"
        Write-Log "Service $Name  $StartupType" "OK"
    } catch {
        Write-Warn "Gagal set $Name`: $($_.Exception.Message)"
    }
}

# 
#   ADMIN CHECK
# 
function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = [System.Security.Principal.WindowsPrincipal]$id
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 
#   NEOOPTIMIZE LOGO
# 
function Write-NeoLogo {
    param([switch]$Compact)

    if ($Compact) {
        Write-Host "$($Global:CYAN)$($Global:BOLD)                              $($Global:RESET)"
        Write-Host "$($Global:CYAN)$($Global:BOLD)                           $($Global:RESET)"
        Write-Host "$($Global:DIM)                               $($Global:RESET)"
        Write-Host "  $($Global:YELLOW)$($Global:BOLD) $($Global:PRODUCT_NAME) v$($Global:PRODUCT_VERSION)  $($Global:PRODUCT_TAGLINE)$($Global:RESET)"
        Write-Separator
        return
    }

    Clear-Host
    Write-Host ""
    Write-Host "$($Global:CYAN)$($Global:BOLD)"
    Write-Host "             "
    Write-Host "     "
    Write-Host "                      "
    Write-Host "                      "
    Write-Host "                "
    Write-Host "                        "
    Write-Host "$($Global:RESET)"
    Write-Host "  $($Global:YELLOW)$($Global:BOLD)                     Windows Optimizer & Agent v$($Global:PRODUCT_VERSION) $($Global:RESET)"
    Write-Host "  $($Global:DIM)                         One-Stop Solution for Computer Technicians$($Global:RESET)"
    Write-Host ""
    Write-Separator "" $Global:CYAN
}

# 
#   FOOTER WITH DONATION
# 
function Write-Footer {
    Write-Host ""
    Write-Separator "" $Global:DIM
    Write-Host "  $($Global:DIM)Reports are available from the NeoOptimize UI Reports button.$($Global:RESET)"
    Write-Separator "" $Global:DIM
}

# 
#   HTML REPORT GENERATOR
# 
function Export-HtmlReport {
    param($Title, $Sections, $OutputPath)
    $safeTitle = ConvertTo-HtmlSafe $Title
    $safeComputer = ConvertTo-HtmlSafe $env:COMPUTERNAME
    $safeUser = ConvertTo-HtmlSafe $env:USERNAME
    $html = @"
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>$safeTitle  NeoOptimize Report</title>
<style>
  :root { --c-bg:#0d1117; --c-surface:#161b22; --c-border:#30363d; --c-cyan:#58d6f5; --c-green:#3fb950; --c-yellow:#d29922; --c-red:#f85149; --c-text:#e6edf3; --c-dim:#8b949e; }
  * { box-sizing:border-box; margin:0; padding:0; }
  body { background:var(--c-bg); color:var(--c-text); font-family:'Segoe UI',system-ui,sans-serif; padding:2rem; }
  .header { border-left:4px solid var(--c-cyan); padding:.75rem 1.25rem; margin-bottom:2rem; }
  .header h1 { font-size:1.75rem; color:var(--c-cyan); }
  .header p  { color:var(--c-dim); font-size:.875rem; margin-top:.25rem; }
  .card { background:var(--c-surface); border:1px solid var(--c-border); border-radius:8px; padding:1.25rem; margin-bottom:1.25rem; }
  .card h2 { font-size:1rem; color:var(--c-cyan); margin-bottom:.75rem; border-bottom:1px solid var(--c-border); padding-bottom:.5rem; }
  .entry { display:flex; align-items:flex-start; padding:.3rem 0; border-bottom:1px solid #21262d; font-size:.85rem; }
  .entry:last-child { border-bottom:none; }
  .badge { padding:.15rem .5rem; border-radius:4px; font-size:.75rem; font-weight:600; margin-right:.75rem; min-width:56px; text-align:center; }
  .OK    { background:#1f4327; color:var(--c-green); }
  .WARN  { background:#3d2f0c; color:var(--c-yellow); }
  .ERROR { background:#3d1212; color:var(--c-red); }
  .INFO  { background:#1a2332; color:var(--c-cyan); }
  .footer { text-align:center; color:var(--c-dim); font-size:.8rem; margin-top:2rem; padding-top:1rem; border-top:1px solid var(--c-border); }
  .footer a { color:var(--c-cyan); text-decoration:none; }
  .sysinfo { display:grid; grid-template-columns:repeat(auto-fill,minmax(220px,1fr)); gap:.75rem; }
  .sysinfo-item { background:#0d1117; border:1px solid var(--c-border); border-radius:6px; padding:.6rem 1rem; }
  .sysinfo-item .label { color:var(--c-dim); font-size:.75rem; text-transform:uppercase; }
  .sysinfo-item .value { color:var(--c-text); font-size:.9rem; font-weight:600; margin-top:.15rem; }
</style>
</head>
<body>
<div class="header">
  <h1> NeoOptimize  $safeTitle</h1>
  <p>Generated: $(Get-Date -Format 'dddd, dd MMMM yyyy HH:mm:ss') | Computer: $safeComputer | User: $safeUser</p>
</div>
$Sections
<div class="footer">
  <p>NeoOptimize v$($Global:PRODUCT_VERSION)  Windows Optimizer & Agent</p>
  <p>Generated locally by NeoOptimize. Use the application Cloud Connectors panel for official pages.</p>
</div>
</body>
</html>
"@
    try {
        $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
        return $true
    } catch { return $false }
}
