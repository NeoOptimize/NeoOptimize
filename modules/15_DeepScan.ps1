#Requires -Version 5.1
<#
.SYNOPSIS
    NeoOptimize Deep Junk, Cache, Package, and Residual Scanner.
.DESCRIPTION
    Scans fixed drives for safe-to-clean junk and report-only residuals.
    Clean mode removes only conservative candidates under known temp/cache roots.
#>

param(
    [ValidateSet("Scan", "Clean")]
    [string]$Mode = "Scan",
    [int]$MinAgeDays = 2,
    [int]$MaxDepth = 16,
    [int]$MaxFiles = 250000,
    [switch]$Aggressive,
    [string]$ArgsJson = ""
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

try { . "$PSScriptRoot\..\lib\Common.ps1" } catch {}

if ($ArgsJson) {
    try {
        $parsedArgs = $ArgsJson | ConvertFrom-Json
        foreach ($name in @("Mode", "MinAgeDays", "MaxDepth", "MaxFiles")) {
            if ($null -ne $parsedArgs.$name) { Set-Variable -Name $name -Value $parsedArgs.$name -Scope Local }
        }
        if ($null -ne $parsedArgs.Aggressive) { $Aggressive = [bool]$parsedArgs.Aggressive }
    } catch {}
}

function Out-Info { param([string]$Message) if (Get-Command Write-Info -ErrorAction SilentlyContinue) { Write-Info $Message } else { Write-Host "  [*] $Message" -ForegroundColor Cyan } }
function Out-OK { param([string]$Message) if (Get-Command Write-OK -ErrorAction SilentlyContinue) { Write-OK $Message } elseif (Get-Command Write-Success -ErrorAction SilentlyContinue) { Write-Success $Message } else { Write-Host "  [+] $Message" -ForegroundColor Green } }
function Out-Warn { param([string]$Message) if (Get-Command Write-Warn -ErrorAction SilentlyContinue) { Write-Warn $Message } else { Write-Host "  [!] $Message" -ForegroundColor Yellow } }
function Out-Step { param([string]$Message) if (Get-Command Write-Step -ErrorAction SilentlyContinue) { Write-Step $Message } else { Write-Host "`n== $Message ==" -ForegroundColor Magenta } }

if (Get-Command Write-ModuleHeader -ErrorAction SilentlyContinue) {
    Write-ModuleHeader "15" "SCAN" "DEEP JUNK SCANNER"
} elseif (Get-Command Write-NeoHeader -ErrorAction SilentlyContinue) {
    Write-NeoHeader "Deep Junk Scanner" "1.1"
} else {
    Write-Host "`nNeoOptimize Deep Junk Scanner v1.1`n" -ForegroundColor Cyan
}

$Script:Now = Get-Date
$Script:Candidates = New-Object System.Collections.Generic.List[object]
$Script:Seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$Script:ScannedFiles = 0
$Script:SkippedDirs = 0
$Script:Errors = 0

$rootDir = Split-Path -Parent $PSScriptRoot
$reportDir = Join-Path $rootDir "reports\deep_scan"
if (-not (Test-Path $reportDir)) { New-Item -Path $reportDir -ItemType Directory -Force | Out-Null }
$reportPath = Join-Path $reportDir ("DeepScan_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

function Get-NormalPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try { return [System.IO.Path]::GetFullPath($Path).TrimEnd("\") } catch { return $Path.TrimEnd("\") }
}

$knownRootsRaw = @(
    $env:TEMP,
    $env:TMP,
    "$env:LOCALAPPDATA\Temp",
    "$env:WINDIR\Temp",
    "$env:WINDIR\Prefetch",
    "$env:WINDIR\Minidump",
    "$env:LOCALAPPDATA\CrashDumps",
    "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
    "$env:LOCALAPPDATA\Microsoft\Windows\WebCache",
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer",
    "$env:LOCALAPPDATA\D3DSCache",
    "$env:LOCALAPPDATA\NVIDIA\DXCache",
    "$env:LOCALAPPDATA\NVIDIA\GLCache",
    "$env:LOCALAPPDATA\AMD\DxCache",
    "$env:PROGRAMDATA\Microsoft\Windows\WER\ReportArchive",
    "$env:PROGRAMDATA\Microsoft\Windows\WER\ReportQueue",
    "$env:PROGRAMDATA\Microsoft\Windows\WER\Temp",
    "$env:PROGRAMDATA\Microsoft\Windows\DeliveryOptimization\Cache",
    "$env:WINDIR\SoftwareDistribution\Download",
    "$env:LOCALAPPDATA\npm-cache",
    "$env:APPDATA\npm-cache",
    "$env:LOCALAPPDATA\pip\Cache",
    "$env:LOCALAPPDATA\Yarn\Cache",
    "$env:LOCALAPPDATA\pnpm\store",
    "$env:USERPROFILE\.cache",
    "$env:USERPROFILE\.nuget\packages",
    "$env:USERPROFILE\.gradle\caches",
    "$env:USERPROFILE\AppData\Local\Microsoft\Windows\Caches"
)

$Script:KnownRoots = @($knownRootsRaw | ForEach-Object { Get-NormalPath $_ } | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)
$Script:ConservativeCleanRoots = @($Script:KnownRoots | Where-Object {
    $_ -notmatch "\\\.nuget\\packages$" -and
    $_ -notmatch "\\\.gradle\\caches$" -and
    $_ -notmatch "\\pnpm\\store$"
})

$Script:ExcludedFragments = @(
    "\windows\winsxs\",
    "\windows\system32\",
    "\windows\syswow64\",
    "\windows\servicing\",
    "\windows\installer\",
    "\program files\",
    "\program files (x86)\",
    "\programdata\microsoft\windows defender\",
    "\system volume information\",
    "\recovery\",
    "\efi\",
    "\boot\",
    "\$windows.~bt\",
    "\$windows.~ws\"
)

function Test-UnderRoot {
    param([string]$Path, [string[]]$Roots)
    $full = Get-NormalPath $Path
    foreach ($root in $Roots) {
        if ($full -and $root -and ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase))) {
            return $true
        }
    }
    return $false
}

function Test-ExcludedPath {
    param([string]$Path)
    $p = ("\{0}\" -f ((Get-NormalPath $Path) -replace '/', '\')).ToLowerInvariant()
    foreach ($fragment in $Script:ExcludedFragments) {
        if ($p.Contains($fragment)) { return $true }
    }
    return $false
}

function Get-FixedDriveRoots {
    $roots = @()
    try {
        $roots = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
            ForEach-Object { "$($_.DeviceID)\" }
    } catch {}
    if (-not $roots) {
        $roots = [System.IO.DriveInfo]::GetDrives() |
            Where-Object { $_.DriveType -eq [System.IO.DriveType]::Fixed -and $_.IsReady } |
            ForEach-Object { $_.RootDirectory.FullName }
    }
    return @($roots | Select-Object -Unique)
}

function Get-Depth {
    param([string]$Root, [string]$Path)
    $fullRoot = (Get-NormalPath $Root).TrimEnd("\")
    $fullPath = Get-NormalPath $Path
    if (-not $fullPath -or -not $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) { return 0 }
    $relative = $fullPath.Substring($fullRoot.Length).Trim("\")
    if (-not $relative) { return 0 }
    return ($relative -split "\\").Count
}

function Get-CandidateKind {
    param([System.IO.FileInfo]$File)
    $name = $File.Name.ToLowerInvariant()
    $path = $File.FullName.ToLowerInvariant()
    $ext = $File.Extension.ToLowerInvariant()

    if ($path -match "\\softwaredistribution\\download\\" -or $path -match "\\deliveryoptimization\\cache\\") { return "windows-update-cache" }
    if ($path -match "\\wer\\" -or $path -match "\\crashdumps\\" -or $path -match "\\minidump\\") { return "crash-report" }
    if ($path -match "\\cache\\" -or $path -match "\\code cache\\" -or $path -match "\\gpucache\\" -or $path -match "\\\.cache\\") { return "app-cache" }
    if ($path -match "\\npm-cache\\" -or $path -match "\\pip\\cache\\" -or $path -match "\\yarn\\cache\\" -or $path -match "\\pnpm\\store\\" -or $path -match "\\\.nuget\\packages\\" -or $path -match "\\\.gradle\\caches\\") { return "package-cache" }
    if ($path -match "\\temp\\" -or $path -match "\\tmp\\") { return "temp" }
    if ($name -in @("thumbs.db", "iconcache.db") -or $name -like "thumbcache_*.db" -or $name -like "iconcache_*.db") { return "shell-cache" }
    if ($ext -in @(".tmp", ".temp", ".dmp", ".etl", ".chk", ".gid")) { return "junk-file" }
    if ($ext -in @(".old", ".bak", ".backup")) { return "residual-backup" }
    if ($ext -eq ".log" -and ($path -match "\\logs?\\" -or $path -match "\\temp\\")) { return "old-log" }
    if ($name.StartsWith("~") -or $name.EndsWith(".tmp")) { return "temporary-office-file" }
    return $null
}

function Add-Candidate {
    param(
        [System.IO.FileInfo]$File,
        [string]$Category,
        [string]$Reason
    )
    if (-not $File -or -not $Category) { return }
    if (-not $Script:Seen.Add($File.FullName)) { return }

    $ageDays = [math]::Round(($Script:Now - $File.LastWriteTime).TotalDays, 1)
    if ($ageDays -lt $MinAgeDays) { return }

    $underKnownRoot = Test-UnderRoot $File.FullName $Script:KnownRoots
    $underCleanRoot = Test-UnderRoot $File.FullName $Script:ConservativeCleanRoots
    $safeByExtension = $File.Extension.ToLowerInvariant() -in @(".tmp", ".temp", ".dmp", ".etl", ".chk", ".gid")
    $safeToClean = $underCleanRoot -or ($Aggressive -and $safeByExtension -and -not (Test-ExcludedPath $File.FullName))

    $Script:Candidates.Add([PSCustomObject]@{
        path = $File.FullName
        category = $Category
        reason = $Reason
        size_mb = [math]::Round(($File.Length / 1MB), 3)
        age_days = $ageDays
        last_write = $File.LastWriteTime.ToString("o")
        safe_to_clean = [bool]$safeToClean
        known_root = [bool]$underKnownRoot
    }) | Out-Null
}

function Scan-Directory {
    param([string]$Root, [bool]$KnownRootOnly = $false)
    if (-not (Test-Path $Root)) { return }

    $queue = New-Object System.Collections.Queue
    $queue.Enqueue((Get-NormalPath $Root))

    while ($queue.Count -gt 0 -and $Script:ScannedFiles -lt $MaxFiles) {
        $dir = [string]$queue.Dequeue()
        if (-not $dir -or (Test-ExcludedPath $dir)) { $Script:SkippedDirs++; continue }

        $depth = Get-Depth -Root $Root -Path $dir
        if ($depth -gt $MaxDepth) { continue }

        try {
            foreach ($filePath in [System.IO.Directory]::EnumerateFiles($dir)) {
                if ($Script:ScannedFiles -ge $MaxFiles) { break }
                $Script:ScannedFiles++
                try {
                    $file = [System.IO.FileInfo]::new($filePath)
                    $kind = Get-CandidateKind $file
                    if ($kind) { Add-Candidate -File $file -Category $kind -Reason "matched $kind rule" }
                } catch { $Script:Errors++ }
            }
        } catch { $Script:Errors++ }

        if ($depth -ge $MaxDepth) { continue }
        try {
            foreach ($subdir in [System.IO.Directory]::EnumerateDirectories($dir)) {
                if (-not (Test-ExcludedPath $subdir)) { $queue.Enqueue($subdir) }
                else { $Script:SkippedDirs++ }
            }
        } catch { $Script:Errors++ }
    }
}

Out-Step "Known cache and package roots"
foreach ($root in $Script:KnownRoots) {
    Out-Info "Scanning $root"
    Scan-Directory -Root $root -KnownRootOnly $true
}

Out-Step "Fixed drive residual scan"
foreach ($drive in Get-FixedDriveRoots) {
    Out-Info "Scanning fixed drive $drive"
    Scan-Directory -Root $drive
}

$deleted = New-Object System.Collections.Generic.List[object]
$deleteErrors = New-Object System.Collections.Generic.List[object]
if ($Mode -eq "Clean") {
    Out-Step "Conservative cleanup"
    foreach ($candidate in @($Script:Candidates | Where-Object { $_.safe_to_clean })) {
        try {
            $size = $candidate.size_mb
            Remove-Item -LiteralPath $candidate.path -Force -ErrorAction Stop
            $deleted.Add([PSCustomObject]@{ path = $candidate.path; size_mb = $size; category = $candidate.category }) | Out-Null
        } catch {
            $deleteErrors.Add([PSCustomObject]@{ path = $candidate.path; error = $_.Exception.Message }) | Out-Null
        }
    }
    Out-OK ("Deleted {0} safe files" -f $deleted.Count)
} else {
    Out-Info "Scan-only mode. Use Mode=Clean for conservative removal."
}

$summary = @($Script:Candidates | Group-Object category | ForEach-Object {
    [PSCustomObject]@{
        category = $_.Name
        count = $_.Count
        size_mb = [math]::Round((($_.Group | Measure-Object size_mb -Sum).Sum), 2)
        safe_count = @($_.Group | Where-Object { $_.safe_to_clean }).Count
        safe_size_mb = [math]::Round((($_.Group | Where-Object { $_.safe_to_clean } | Measure-Object size_mb -Sum).Sum), 2)
    }
} | Sort-Object size_mb -Descending)

$top = @($Script:Candidates | Sort-Object size_mb -Descending | Select-Object -First 50)
$totalSize = [math]::Round((($Script:Candidates | Measure-Object size_mb -Sum).Sum), 2)
$safeSize = [math]::Round((($Script:Candidates | Where-Object { $_.safe_to_clean } | Measure-Object size_mb -Sum).Sum), 2)
$deletedSize = [math]::Round((($deleted | Measure-Object size_mb -Sum).Sum), 2)

$result = [PSCustomObject]@{
    scan_time = (Get-Date).ToString("o")
    mode = $Mode
    min_age_days = $MinAgeDays
    max_depth = $MaxDepth
    max_files = $MaxFiles
    aggressive = [bool]$Aggressive
    fixed_drives = @(Get-FixedDriveRoots)
    scanned_files = $Script:ScannedFiles
    skipped_dirs = $Script:SkippedDirs
    errors = $Script:Errors
    candidate_count = $Script:Candidates.Count
    candidate_size_mb = $totalSize
    safe_to_clean_count = @($Script:Candidates | Where-Object { $_.safe_to_clean }).Count
    safe_to_clean_size_mb = $safeSize
    deleted_count = $deleted.Count
    deleted_size_mb = $deletedSize
    delete_errors = @($deleteErrors)
    summary = @($summary)
    top_candidates = @($top)
    report_path = $reportPath
    safety = "Clean mode deletes only known temp/cache roots unless Aggressive is explicitly enabled. Package stores are reported by default."
}

$json = $result | ConvertTo-Json -Depth 8
$json | Set-Content -Path $reportPath -Encoding UTF8

Out-Step "Summary"
Out-OK ("Candidates: {0} files, {1} MB" -f $result.candidate_count, $result.candidate_size_mb)
Out-OK ("Conservative cleanable: {0} files, {1} MB" -f $result.safe_to_clean_count, $result.safe_to_clean_size_mb)
if ($Mode -eq "Clean") { Out-OK ("Deleted: {0} files, {1} MB" -f $result.deleted_count, $result.deleted_size_mb) }
Out-Info "Report: $reportPath"

$result | ConvertTo-Json -Depth 8 -Compress | Write-Output
