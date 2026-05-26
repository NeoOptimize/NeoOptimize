
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

# ═══════════════════════════════════════════════════════════════
#   ANSI COLOR PALETTE
# ═══════════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════════
#   BRANDING
# ═══════════════════════════════════════════════════════════════
$Global:PRODUCT_NAME    = "NeoOptimize"
$Global:PRODUCT_VERSION = "1.0.0"
$Global:PRODUCT_TAGLINE = "Windows Optimizer & Agent"
$Global:PRODUCT_EMAIL   = "neooptimizeofficial@gmail.com"
$Global:PRODUCT_BUYMECOFFEE = "https://buymeacoffee.com/nol.eight"
$Global:PRODUCT_SAWERIA     = "https://saweria.co/dtechtive"
$Global:PRODUCT_DANA        = "https://ik.imagekit.io/dtechtive/Dana"

# ═══════════════════════════════════════════════════════════════
#   RUNTIME FLAGS
# ═══════════════════════════════════════════════════════════════
if ($null -eq $Global:NeoOptimizeNonInteractive) { $Global:NeoOptimizeNonInteractive = $false }
if ($null -eq $Global:NeoOptimizeSkipPause)      { $Global:NeoOptimizeSkipPause      = $false }
if ($null -eq $Global:NeoOptimizeAssumeYes)      { $Global:NeoOptimizeAssumeYes      = $false }
if ($null -eq $Global:NeoOptimizeConfirmAll)     { $Global:NeoOptimizeConfirmAll     = $false }

# ═══════════════════════════════════════════════════════════════
#   LOGGING
# ═══════════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════════
#   PRINT HELPERS
# ═══════════════════════════════════════════════════════════════
function Write-OK   { param($m) Write-Host "  $($Global:GREEN)✔$($Global:RESET) $m"; Write-Log $m "OK" }
function Write-Warn { param($m) Write-Host "  $($Global:YELLOW)⚠$($Global:RESET) $m"; Write-Log $m "WARN" }
function Write-Err  { param($m) Write-Host "  $($Global:RED)✘$($Global:RESET) $m"; Write-Log $m "ERROR" }
function Write-Info { param($m) Write-Host "  $($Global:CYAN)›$($Global:RESET) $m"; Write-Log $m "INFO" }
function Write-Skip { param($m) Write-Host "  $($Global:DIM)─ $m (skipped)$($Global:RESET)" }
function Write-Step { param($m) Write-Host "  $($Global:MAGENTA)◈$($Global:RESET) $($Global:BOLD)$m$($Global:RESET)" }

function Write-Separator {
    param($Char = "─", $Color = $Global:DIM)
    Write-Host "$Color$($Char * 68)$($Global:RESET)"
}

function Write-SectionHeader {
    param($Icon, $Title, $Subtitle = "")
    Write-Host ""
    Write-Host "$($Global:CYAN)$($Global:BOLD)  ╔══════════════════════════════════════════════════════════════════╗$($Global:RESET)"
    Write-Host "$($Global:CYAN)$($Global:BOLD)  ║  $Icon $($Title.PadRight(63))║$($Global:RESET)"
    if ($Subtitle) {
        Write-Host "$($Global:DIM)  ║  $($Subtitle.PadRight(65))║$($Global:RESET)"
    }
    Write-Host "$($Global:CYAN)$($Global:BOLD)  ╚══════════════════════════════════════════════════════════════════╝$($Global:RESET)"
    Write-Host ""
}

function Write-ModuleHeader {
    param($Number, $Icon, $Title)
    Clear-Host
    Write-NeoLogo -Compact
    Write-Host ""
    Write-Host "  $($Global:BG_BLUE)$($Global:WHITE)$($Global:BOLD)  MODULE $Number — $Icon $Title  $($Global:RESET)"
    Write-Host ""
}

function Show-Progress {
    param($Current, $Total, $Label = "")
    $pct  = [math]::Round(($Current / $Total) * 100)
    $fill = [math]::Round(($Current / $Total) * 40)
    $bar  = "█" * $fill + "░" * (40 - $fill)
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

function ConvertTo-HtmlSafe {
    param($Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

# ═══════════════════════════════════════════════════════════════
#   REGISTRY HELPER
# ═══════════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════════
#   SYSTEM SNAPSHOT
# ═══════════════════════════════════════════════════════════════
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
        RAMFree      = [math]::Round($os.FreePhysicalMemory / 1MB / 1024, 2)
        GPU          = $gpu.Name
        Uptime       = (Get-Date) - $os.LastBootUpTime
        BIOSVersion  = $bios.SMBIOSBIOSVersion
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
    }
}

# ═══════════════════════════════════════════════════════════════
#   RESTORE POINT
# ═══════════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════════
#   FOLDER SIZE HELPER
# ═══════════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════════
#   SERVICE HELPER
# ═══════════════════════════════════════════════════════════════
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
            "Disabled"  { "$($Global:RED)✘$($Global:RESET)" }
            "Automatic" { "$($Global:GREEN)✔$($Global:RESET)" }
            "Manual"    { "$($Global:YELLOW)◔$($Global:RESET)" }
            default     { "$($Global:DIM)●$($Global:RESET)" }
        }
        Write-Host "  $icon [$($StartupType.PadRight(9))] $display"
        Write-Log "Service $Name → $StartupType" "OK"
    } catch {
        Write-Warn "Gagal set $Name`: $($_.Exception.Message)"
    }
}

# ═══════════════════════════════════════════════════════════════
#   ADMIN CHECK
# ═══════════════════════════════════════════════════════════════
function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = [System.Security.Principal.WindowsPrincipal]$id
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ═══════════════════════════════════════════════════════════════
#   NEOOPTIMIZE LOGO
# ═══════════════════════════════════════════════════════════════
function Write-NeoLogo {
    param([switch]$Compact)

    if ($Compact) {
        Write-Host "$($Global:CYAN)$($Global:BOLD)  ▄   ▄ ▄▄▄  ▄▄▄       ▄▄▄  ▄▄▄  ▄▄▄▄  ▄▄▄  ▄▄   ▄▄ ▄▄▄ ▄▄▄  ▄▄▄$($Global:RESET)"
        Write-Host "$($Global:CYAN)$($Global:BOLD)  █▀▄▀█ █▄▄  █ █  ▄▀▀  █  █ █▄▄█  █   █  █ █ ▀▄▀ █   ▀▄▀ █▄▄$($Global:RESET)"
        Write-Host "$($Global:DIM)  ▀   ▀ █▄▄  ▀▀▀  ▀▄▄  ▀▀▀ █  █  █   ▀▀▀ ▀  ▀  ▀▄▄ ▀   ▄▄▀  ██▄$($Global:RESET)"
        Write-Host "  $($Global:YELLOW)$($Global:BOLD)⚡ $($Global:PRODUCT_NAME) v$($Global:PRODUCT_VERSION) — $($Global:PRODUCT_TAGLINE)$($Global:RESET)  $($Global:DIM)| $($Global:PRODUCT_EMAIL)$($Global:RESET)"
        Write-Separator
        return
    }

    Clear-Host
    Write-Host ""
    Write-Host "$($Global:CYAN)$($Global:BOLD)"
    Write-Host "  ███╗   ██╗███████╗ ██████╗  ██████╗ ██████╗ ████████╗██╗███╗   ███╗██╗███████╗███████╗"
    Write-Host "  ████╗  ██║██╔════╝██╔═══██╗██╔═══██╗██╔══██╗╚══██╔══╝██║████╗ ████║██║╚══███╔╝██╔════╝"
    Write-Host "  ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██████╔╝   ██║   ██║██╔████╔██║██║  ███╔╝ █████╗  "
    Write-Host "  ██║╚██╗██║██╔══╝  ██║   ██║██║   ██║██╔═══╝    ██║   ██║██║╚██╔╝██║██║ ███╔╝  ██╔══╝  "
    Write-Host "  ██║ ╚████║███████╗╚██████╔╝╚██████╔╝██║        ██║   ██║██║ ╚═╝ ██║██║███████╗███████╗"
    Write-Host "  ╚═╝  ╚═══╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝        ╚═╝   ╚═╝╚═╝     ╚═╝╚═╝╚══════╝╚══════╝"
    Write-Host "$($Global:RESET)"
    Write-Host "  $($Global:YELLOW)$($Global:BOLD)                    ⚡ Windows Optimizer & Agent v$($Global:PRODUCT_VERSION) ⚡$($Global:RESET)"
    Write-Host "  $($Global:DIM)                         One-Stop Solution for Computer Technicians$($Global:RESET)"
    Write-Host ""
    Write-Separator "═" $Global:CYAN
}

# ═══════════════════════════════════════════════════════════════
#   FOOTER WITH DONATION
# ═══════════════════════════════════════════════════════════════
function Write-Footer {
    Write-Host ""
    Write-Separator "─" $Global:DIM
    Write-Host "  $($Global:DIM)📧 $($Global:PRODUCT_EMAIL)$($Global:RESET)"
    Write-Host "  $($Global:YELLOW)☕ Dukung developer:$($Global:RESET)  $($Global:DIM)BuyMeACoffee · Saweria · Dana$($Global:RESET)"
    Write-Separator "─" $Global:DIM
}

# ═══════════════════════════════════════════════════════════════
#   HTML REPORT GENERATOR
# ═══════════════════════════════════════════════════════════════
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
<title>$safeTitle — NeoOptimize Report</title>
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
  <h1>⚡ NeoOptimize — $safeTitle</h1>
  <p>Generated: $(Get-Date -Format 'dddd, dd MMMM yyyy HH:mm:ss') | Computer: $safeComputer | User: $safeUser</p>
</div>
$Sections
<div class="footer">
  <p>NeoOptimize v$($Global:PRODUCT_VERSION) — Windows Optimizer & Agent</p>
  <p>📧 <a href="mailto:$($Global:PRODUCT_EMAIL)">$($Global:PRODUCT_EMAIL)</a> &nbsp;|&nbsp;
     ☕ <a href="$($Global:PRODUCT_BUYMECOFFEE)" target="_blank">BuyMeACoffee</a> &nbsp;|&nbsp;
     🙏 <a href="$($Global:PRODUCT_SAWERIA)" target="_blank">Saweria</a> &nbsp;|&nbsp;
     💰 <a href="$($Global:PRODUCT_DANA)" target="_blank">Dana</a>
  </p>
</div>
</body>
</html>
"@
    try {
        $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
        return $true
    } catch { return $false }
}
