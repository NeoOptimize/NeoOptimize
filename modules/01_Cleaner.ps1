
#Requires -RunAsAdministrator
<# MODULE 01 — SYSTEM CLEANER #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "01" "🧹" "SYSTEM CLEANER"
Write-Info "Memulai pembersihan sistem..."
Write-Host ""

$totalFreed = 0
$cleaned    = 0

function Remove-FolderContents {
    param($Path, $Label)
    if (-not (Test-Path $Path)) { return }
    $before = Get-FolderSizeMB $Path
    Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $after  = Get-FolderSizeMB $Path
    $freed  = [math]::Round($before - $after, 2)
    $script:totalFreed += $freed
    $script:cleaned++
    if ($freed -gt 0) {
        Write-OK "$Label  $($Global:DIM)(freed ${freed} MB)$($Global:RESET)"
    } else {
        Write-Skip "$Label (sudah bersih)"
    }
}

# ── 1. Temp & Prefetch ─────────────────────────────────────────────────────────
Write-Step "TEMP & SYSTEM FILES"
Write-Host ""
$tempPaths = @(
    @{P="$env:TEMP";                                        L="User Temp (%TEMP%)"},
    @{P="$env:TMP";                                         L="User Temp (%TMP%)"},
    @{P="C:\Windows\Temp";                                  L="Windows Temp"},
    @{P="C:\Windows\Prefetch";                              L="Windows Prefetch"},
    @{P="$env:LOCALAPPDATA\Temp";                           L="LocalAppData Temp"},
    @{P="$env:LOCALAPPDATA\CrashDumps";                     L="Crash Dumps"},
    @{P="C:\Windows\Minidump";                              L="Minidump Files"},
    @{P="$env:SYSTEMROOT\Downloaded Program Files";         L="Downloaded Program Files"},
    @{P="$env:LOCALAPPDATA\Microsoft\Windows\INetCache";    L="Internet Cache (IE/Edge Legacy)"},
    @{P="$env:LOCALAPPDATA\Microsoft\Windows\WebCache";     L="WebCache"}
)
foreach ($t in $tempPaths) { Remove-FolderContents $t.P $t.L }

# ── 2. Browser Cache ───────────────────────────────────────────────────────────
Write-Host ""
Write-Step "BROWSER CACHE"
Write-Host ""
	$browsers = @(
	    @{P="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache";              L="Chrome Cache"},
	    @{P="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache";         L="Chrome Code Cache"},
	    @{P="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache";           L="Chrome GPU Cache"},
	    @{P="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache";             L="Edge Cache"},
	    @{P="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache";        L="Edge Code Cache"},
	    @{P="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache";L="Brave Cache"},
	    @{P="$env:LOCALAPPDATA\Opera Software\Opera Stable\Cache";                  L="Opera Cache"}
	)
	foreach ($b in $browsers) { Remove-FolderContents $b.P $b.L }

	$ffProfiles = "$env:APPDATA\Mozilla\Firefox\Profiles"
	if (Test-Path $ffProfiles) {
	    Get-ChildItem -Path $ffProfiles -Directory -ErrorAction SilentlyContinue | ForEach-Object {
	        foreach ($cacheName in @("cache2", "startupCache", "thumbnails", "OfflineCache")) {
	            Remove-FolderContents (Join-Path $_.FullName $cacheName) "Firefox $cacheName ($($_.Name))"
	        }
	    }
	} else {
	    Write-Skip "Firefox cache"
	}

# ── 3. Windows Update Cache ────────────────────────────────────────────────────
Write-Host ""
Write-Step "WINDOWS UPDATE CACHE"
Write-Host ""
$wuServices = @("wuauserv","bits","dosvc")
foreach ($s in $wuServices) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
Remove-FolderContents "C:\Windows\SoftwareDistribution\Download" "WU Download Cache"
foreach ($s in $wuServices) { Start-Service -Name $s -ErrorAction SilentlyContinue }

# ── 4. Windows Error Reports ───────────────────────────────────────────────────
Write-Host ""
Write-Step "WINDOWS ERROR REPORTS"
Write-Host ""
$werPaths = @(
    @{P="C:\ProgramData\Microsoft\Windows\WER\ReportArchive";  L="WER Archive"},
    @{P="C:\ProgramData\Microsoft\Windows\WER\ReportQueue";    L="WER Queue"},
    @{P="$env:LOCALAPPDATA\Microsoft\Windows\WER";             L="WER Local"},
    @{P="C:\ProgramData\Microsoft\Windows\WER\Temp";           L="WER Temp"}
)
foreach ($w in $werPaths) { Remove-FolderContents $w.P $w.L }

# ── 5. Event Logs ──────────────────────────────────────────────────────────────
	Write-Host ""
	Write-Step "EVENT LOGS"
	Write-Host ""
	if (Confirm-NeoAction "  Bersihkan Windows Event Logs? Riwayat troubleshooting akan hilang." $false) {
	    $logList  = wevtutil el 2>$null
	    $logCount = 0
	    if ($logList) {
	        foreach ($log in $logList) {
	            wevtutil cl "$log" 2>$null
	            $logCount++
	        }
	    }
	    Write-OK "Cleared $logCount Windows Event Logs"
	    $cleaned++
	} else {
	    Write-Skip "Event Logs dipertahankan"
	}

# ── 6. Caches & Thumbnails ─────────────────────────────────────────────────────
Write-Host ""
Write-Step "SYSTEM CACHES"
Write-Host ""

# DNS
ipconfig /flushdns 2>&1 | Out-Null
Write-OK "DNS Cache flushed"

# ARP
netsh interface ip delete arpcache 2>&1 | Out-Null
Write-OK "ARP Cache cleared"

# Font cache rebuild
Stop-Service FontCache -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\System32\FNTCACHE.DAT" -Force -ErrorAction SilentlyContinue
Start-Service FontCache -ErrorAction SilentlyContinue
Write-OK "Font Cache rebuilt"

	# Icon cache (kill explorer briefly)
	if (Confirm-NeoAction "  Reset icon/thumbnail cache? Explorer akan restart singkat." $false) {
	    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
	    Start-Sleep -Milliseconds 600
	    Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
	    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db" -Force -ErrorAction SilentlyContinue
	    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
	    Start-Process explorer.exe -ErrorAction SilentlyContinue
	    Write-OK "Icon & Thumbnail cache cleared"
	} else {
	    Write-Skip "Icon & Thumbnail cache"
	}

# ── 7. Recycle Bin ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Step "RECYCLE BIN"
Write-Host ""
try {
    Clear-RecycleBin -Force -ErrorAction Stop
    Write-OK "Recycle Bin emptied"
} catch {
    Write-Warn "Recycle Bin: $($_.Exception.Message)"
}

# ── 8. Windows.old check ───────────────────────────────────────────────────────
Write-Host ""
Write-Step "WINDOWS.OLD CHECK"
Write-Host ""
if (Test-Path "C:\Windows.old") {
    $wOldSize = Get-FolderSizeMB "C:\Windows.old"
    Write-Warn "Windows.old ditemukan: ${wOldSize} MB"
    Write-Info "Gunakan Disk Cleanup → 'Previous Windows installation(s)' untuk hapus aman"
} else {
    Write-OK "Tidak ada Windows.old"
}

# ── 9. Automated Disk Cleanup ──────────────────────────────────────────────────
Write-Host ""
Write-Step "AUTOMATED DISK CLEANUP (CleanMgr)"
Write-Host ""
$cleanFlags = @(
    "Active Setup Temp Folders","BranchCache","Content Indexer Cleaner",
    "Device Driver Packages","Downloaded Program Files","Internet Cache Files",
    "Memory Dump Files","Old ChkDsk Files","Previous Installations",
    "Recycle Bin","Setup Log Files","System error memory dump files",
    "System error minidump files","Temporary Files","Temporary Setup Files",
    "Thumbnail Cache","Update Cleanup","Windows Defender",
    "Windows Error Reporting Archive Files","Windows Error Reporting Queue Files",
    "Windows ESD installation files","Windows Upgrade Log Files"
)
$regBase = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
foreach ($f in $cleanFlags) {
	    $rp = Join-Path $regBase $f
	    if (Test-Path $rp) {
	        New-ItemProperty -Path $rp -Name StateFlags0099 -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
	    }
	}
Write-Info "Menjalankan CleanMgr (harap tunggu)..."
Start-Process cleanmgr.exe -ArgumentList "/sagerun:99" -Wait -ErrorAction SilentlyContinue
Write-OK "Disk Cleanup selesai"

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Separator "═" $Global:GREEN
Write-Host ""
Write-Host "  $($Global:GREEN)$($Global:BOLD)  ✅ SYSTEM CLEANER SELESAI$($Global:RESET)"
Write-Host "  $($Global:WHITE)  Total dibebaskan : $($Global:GREEN)$($Global:BOLD)${totalFreed} MB$($Global:RESET)"
Write-Host "  $($Global:WHITE)  Item dibersihkan : $($Global:CYAN)$cleaned$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
