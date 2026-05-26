
#Requires -RunAsAdministrator
<# MODULE 08 — POWER PLAN & GAMING MODE #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "08" "🔋" "POWER PLAN & GAMING MODE"

# ── Current Plan Info ──────────────────────────────────────────────────────────
Write-Step "POWER PLAN AKTIF SEKARANG"
Write-Host ""
$activeLine = powercfg /getactivescheme 2>&1
Write-Host "  $($Global:DIM)$activeLine$($Global:RESET)"
Write-Host ""

Write-Host "  $($Global:WHITE)$($Global:BOLD)Pilih Power Plan:$($Global:RESET)"
Write-Host ""
Write-Host "  $($Global:CYAN)[1]$($Global:RESET) ⚡ ULTIMATE PERFORMANCE  — Hidden Windows plan, zero throttle"
Write-Host "  $($Global:CYAN)[2]$($Global:RESET) 🔥 HIGH PERFORMANCE      — Standard max performance"
Write-Host "  $($Global:CYAN)[3]$($Global:RESET) 🎮 NEOOPTIMIZE GOD MODE  — Custom plan: CPU 100%, hibernate off"
Write-Host "  $($Global:CYAN)[4]$($Global:RESET) ⚖️  BALANCED              — Windows default"
Write-Host "  $($Global:CYAN)[5]$($Global:RESET) 🔋 POWER SAVER           — Laptop hemat daya"
Write-Host "  $($Global:CYAN)[6]$($Global:RESET) 📊 Power Audit (HTML)    — Analisis konsumsi daya"
Write-Host "  $($Global:CYAN)[7]$($Global:RESET) 🧹 Hapus Custom Plans    — Bersihkan plan buatan"
Write-Host ""
	$choice = Read-NeoChoice "  Pilihan [1-7]" @("1","2","3","4","5","6","7") "4"
	$applyGamingTweaks = $choice -in @("1","2","3")

$GUID_ULTIMATE   = "e9a42b02-d5df-448d-aa00-03f14749eb61"
$GUID_HIGH       = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
$GUID_BALANCED   = "381b4222-f694-41f0-9685-ff5bb260df2e"
$GUID_POWERSAVER = "a1841308-3541-4fab-bc81-f71556f20b4a"

switch ($choice) {

    "1" { # ULTIMATE
        Write-Host ""
        Write-Step "ULTIMATE PERFORMANCE"
        Write-Host ""
        $result = powercfg /duplicatescheme $GUID_ULTIMATE 2>&1
        if ($result -match "\{([0-9a-f-]+)\}") {
            $newGuid = $Matches[1]
            powercfg /setactive $newGuid 2>&1 | Out-Null
            powercfg /changename $newGuid "NeoOptimize — Ultimate" "Maximum system performance. No CPU throttle." 2>&1 | Out-Null
            Write-OK "Ultimate Performance plan aktif (GUID: $newGuid)"
        } else {
            powercfg /setactive $GUID_ULTIMATE 2>&1 | Out-Null
            Write-OK "Ultimate Performance activated"
        }
    }

    "2" { # HIGH PERFORMANCE
        Write-Host ""
        Write-Step "HIGH PERFORMANCE"
        Write-Host ""
        powercfg /setactive $GUID_HIGH 2>&1 | Out-Null
        Write-OK "High Performance plan aktif"
    }

    "3" { # CUSTOM GOD MODE
        Write-Host ""
        Write-Step "NEOOPTIMIZE GOD MODE — CUSTOM PLAN"
        Write-Host ""
        $raw = powercfg /duplicatescheme $GUID_HIGH 2>&1
        $gm  = if ($raw -match "\{([0-9a-f-]+)\}") { $Matches[1] } else { $GUID_HIGH }

        powercfg /changename $gm "⚡ NeoOptimize GOD MODE" "Custom: CPU 100%, Zero Sleep, Low Latency" 2>&1 | Out-Null

        # CPU Min/Max = 100%
        powercfg /setacvalueindex $gm 54533251-82be-4824-96c1-47b60b740d00 bc5038f7-23e0-4960-96da-33abaf5935ec 100 2>&1 | Out-Null
        powercfg /setacvalueindex $gm 54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c 100 2>&1 | Out-Null

        # Sleep = never
        powercfg /setacvalueindex $gm 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0 2>&1 | Out-Null
        # Hibernate = never
        powercfg /setacvalueindex $gm 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 0 2>&1 | Out-Null
        powercfg /h off 2>&1 | Out-Null

        # Disk never sleep
        powercfg /setacvalueindex $gm 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0 2>&1 | Out-Null

        # Display off = 20 minutes
        powercfg /setacvalueindex $gm 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 1200 2>&1 | Out-Null

        # USB selective suspend = off
        powercfg /setacvalueindex $gm 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null

        # PCI-E ASPM = off
        powercfg /setacvalueindex $gm 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 2>&1 | Out-Null

        # Wireless = max performance
        powercfg /setacvalueindex $gm 19caa586-fa36-49f1-be6f-e959b193a7b6 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 2>&1 | Out-Null

        powercfg /setactive $gm 2>&1 | Out-Null
        Write-OK "⚡ NeoOptimize GOD MODE plan aktif"
        Write-Info "CPU Min=100%, Sleep=off, Hibernate=off, USB-suspend=off, PCI-E ASPM=off"
    }

    "4" { powercfg /setactive $GUID_BALANCED 2>&1 | Out-Null;   Write-OK "Balanced plan aktif" }
    "5" { powercfg /setactive $GUID_POWERSAVER 2>&1 | Out-Null; Write-OK "Power Saver plan aktif" }

    "6" { # AUDIT
        Write-Host ""
        Write-Step "POWER AUDIT"
        Write-Host ""
        $auditPath = "$PSScriptRoot\..\reports\PowerAudit_$(Get-Date -f 'yyyyMMdd_HHmmss').html"
        if (-not (Test-Path "$PSScriptRoot\..\reports")) {
            New-Item -Path "$PSScriptRoot\..\reports" -ItemType Directory -Force | Out-Null
        }
	        Write-Info "Generating power audit (10 detik)..."
        powercfg /energy /output $auditPath /duration 10 2>&1 | Out-Null
        if (Test-Path $auditPath) {
            Write-OK "Laporan: $auditPath"
            Start-Process $auditPath -ErrorAction SilentlyContinue
        } else {
            Write-Warn "Audit gagal atau memerlukan lebih lama"
        }
    }

    "7" { # CLEAN CUSTOM PLANS
        Write-Host ""
        Write-Step "HAPUS CUSTOM POWER PLANS"
        Write-Host ""
        $plans = powercfg /list 2>&1
	        $protectedPlans = @($GUID_BALANCED, $GUID_HIGH, $GUID_POWERSAVER, $GUID_ULTIMATE)
	        $plans | Select-String "\{([0-9a-f-]+)\}" | ForEach-Object {
	            $guid = $_.Matches[0].Groups[1].Value.ToLowerInvariant()
	            if ($protectedPlans -notcontains $guid) {
	                powercfg /setactive $GUID_BALANCED 2>&1 | Out-Null
	                $result = powercfg /delete $guid 2>&1
                if ($result -notmatch "error") {
                    Write-OK "Deleted: $guid"
                }
            }
        }
        Write-OK "Custom plans dibersihkan"
    }
}

	if ($applyGamingTweaks) {
	# ── Registry Gaming Tweaks ─────────────────────────────────────────────────────
	Write-Host ""
	Write-Step "GAMING REGISTRY TWEAKS"
	Write-Host ""

# Disable Dynamic Tick
bcdedit /set disabledynamictick yes 2>&1 | Out-Null
Write-OK "Dynamic Tick: DISABLED (lower timer latency)"

bcdedit /set useplatformclock false 2>&1 | Out-Null
Write-OK "Platform Clock: DISABLED"

bcdedit /set tscsyncpolicy enhanced 2>&1 | Out-Null
Write-OK "TSC Sync Policy: Enhanced"

# MMCSS — Games
$gamesPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
if (-not (Test-Path $gamesPath)) { New-Item -Path $gamesPath -Force | Out-Null }
	Set-Reg $gamesPath "GPU Priority"         8       "DWord" | Out-Null
	Set-Reg $gamesPath "Priority"             6       "DWord" | Out-Null
	Set-Reg $gamesPath "Clock Rate"           10000   "DWord" | Out-Null
	Set-Reg $gamesPath "Scheduling Category"  "High"  "String" | Out-Null
	Set-Reg $gamesPath "SFIO Priority"        "High"  "String" | Out-Null
	Set-Reg $gamesPath "Affinity"             0       "DWord" | Out-Null
	Set-Reg $gamesPath "Background Only"      "False" "String" | Out-Null
Write-OK "MMCSS Games: GPU Priority=8, Scheduling=High, SFIO=High"

$mmPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
Set-Reg $mmPath "SystemResponsiveness"    0
Set-Reg $mmPath "NetworkThrottlingIndex"  0xffffffff
Write-OK "MMCSS: SystemResponsiveness=0, NetworkThrottling=OFF"

# Hardware GPU Scheduling
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2
Write-OK "Hardware GPU Scheduling: ENABLED"

# Processor Priority
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38
Write-OK "Processor scheduling: Foreground programs"

# ── Mouse / Input Tweaks ──────────────────────────────────────────────────────
Write-Host ""
Write-Step "MOUSE & INPUT LATENCY"
Write-Host ""
Set-Reg "HKCU:\Control Panel\Mouse" "MouseSpeed"    0
Set-Reg "HKCU:\Control Panel\Mouse" "MouseThreshold1" 0
Set-Reg "HKCU:\Control Panel\Mouse" "MouseThreshold2" 0
Write-OK "Enhanced Pointer Precision: DISABLED (raw input)"

# ── Xbox Game Bar Off ──────────────────────────────────────────────────────────
Write-Host ""
Write-Step "XBOX GAME BAR & DVR"
Write-Host ""
Set-Reg "HKCU:\Software\Microsoft\GameBar" "UseNexusForGameBarEnabled" 0
Set-Reg "HKCU:\Software\Microsoft\GameBar" "ShowStartupPanel" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0
Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode" 2
Write-OK "Xbox Game Bar & DVR: DISABLED"

# ── Fast Startup ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Step "FAST STARTUP"
Write-Host ""
	Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 1
	Write-OK "Fast Startup (Hybrid Boot): ENABLED"
	} else {
	    Write-Host ""
	    Write-Step "GAMING REGISTRY TWEAKS"
	    Write-Skip "Tidak diterapkan untuk pilihan ini"
	}

	# ── Active Plan Confirm ────────────────────────────────────────────────────────
Write-Host ""
Write-Step "PLAN AKTIF SEKARANG"
Write-Host ""
powercfg /getactivescheme 2>&1 | ForEach-Object { Write-Host "  $($Global:CYAN)$_$($Global:RESET)" }

Write-Host ""
Write-Separator "═" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)  ✅ POWER & GAMING MODE SELESAI$($Global:RESET)"
Write-Host ""
Write-Host "  $($Global:YELLOW)⚠  Restart untuk efek penuh bcdedit & GPU scheduling.$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
