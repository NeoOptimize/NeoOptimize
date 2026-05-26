
#Requires -RunAsAdministrator
<# MODULE 07  UPDATE & DRIVER MANAGER #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "07" "" "UPDATE & DRIVER MANAGER"

Write-Host "  $($Global:WHITE)$($Global:BOLD)Pilih Tindakan:$($Global:RESET)"
Write-Host ""
Write-Host "  $($Global:CYAN)[1]$($Global:RESET)   Cek & Install Windows Updates"
Write-Host "  $($Global:CYAN)[2]$($Global:RESET)  Set Update ke MANUAL (no auto-restart)"
Write-Host "  $($Global:CYAN)[3]$($Global:RESET)   Pause Updates 35 hari"
Write-Host "  $($Global:CYAN)[4]$($Global:RESET)  Block Feature Updates (security saja)"
Write-Host "  $($Global:CYAN)[5]$($Global:RESET)  Audit Driver Terpasang"
Write-Host "  $($Global:CYAN)[6]$($Global:RESET)  Bersihkan Driver Lama (PnPUtil)"
Write-Host "  $($Global:CYAN)[7]$($Global:RESET)  Cek & Upgrade Software (winget)"
Write-Host "  $($Global:CYAN)[8]$($Global:RESET)  Export Laporan Driver (HTML)"
Write-Host "  $($Global:CYAN)[9]$($Global:RESET)  Kembalikan Update ke Default"
	Write-Host "  $($Global:CYAN)[0]$($Global:RESET)  Preset Aman (2+4, tanpa hapus driver)"
	Write-Host ""
	$choice = Read-NeoChoice "  Pilihan [0-9]" @("0","1","2","3","4","5","6","7","8","9") "2"

switch ($choice) {

    "1" { # CHECK UPDATES
        Write-Host ""
        Write-Step "CEK WINDOWS UPDATES"
        Write-Host ""
        Write-Info "Menginstal PSWindowsUpdate jika belum ada..."
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue | Out-Null
            Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction SilentlyContinue
        }
        try {
            Import-Module PSWindowsUpdate -ErrorAction Stop
            Write-Info "Mengecek update tersedia..."
            $updates = Get-WindowsUpdate -ErrorAction Stop
            if ($updates.Count -eq 0) {
                Write-OK "Sistem sudah up to date!"
            } else {
                Write-Warn "$($updates.Count) update tersedia:"
                $updates | ForEach-Object { Write-Host "  $($Global:DIM)   $($_.Title)$($Global:RESET)" }
	                if (Confirm-NeoAction "  Install semua update?" $false) {
	                    Get-WindowsUpdate -AcceptAll -Install -AutoReboot:$false -ErrorAction SilentlyContinue
	                    Write-OK "Update selesai diinstall"
	                }
            }
        } catch {
            Write-Warn "PSWindowsUpdate tidak tersedia. Cek manual via Settings  Windows Update."
        }
    }

    "2" { # MANUAL UPDATE
        Write-Host ""
        Write-Step "SET UPDATE KE MANUAL"
        Write-Host ""
        $wuAU = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        Set-Reg $wuAU "NoAutoUpdate"                1
        Set-Reg $wuAU "AUOptions"                   2   # Notify only
        Set-Reg $wuAU "NoAutoRebootWithLoggedOnUsers" 1
        Set-Reg $wuAU "RebootWarningTimeoutEnabled"  1
        Set-Reg $wuAU "RebootWarningTimeout"         240
        Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" 0
        Write-OK "Windows Update  MANUAL NOTIFY ONLY (no auto-download/restart)"
    }

    "3" { # PAUSE UPDATES
        Write-Host ""
        Write-Step "PAUSE UPDATES 35 HARI"
        Write-Host ""
        $pause = (Get-Date).AddDays(35).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $now   = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        Set-Reg "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "PauseUpdatesExpiryTime"              $pause "String"
        Set-Reg "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "PauseFeatureUpdatesStartTime"        $now   "String"
        Set-Reg "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "PauseQualityUpdatesStartTime"        $now   "String"
        Set-Reg "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "PauseFeatureUpdatesEndTime"          $pause "String"
        Set-Reg "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "PauseQualityUpdatesEndTime"          $pause "String"
        Write-OK "Updates di-pause sampai: $((Get-Date).AddDays(35).ToString('dd MMM yyyy'))"
    }

    "4" { # BLOCK FEATURE UPDATES
        Write-Host ""
        Write-Step "BLOCK FEATURE UPDATES"
        Write-Host ""
        $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        $curVer = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion
        $curBld = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
        Set-Reg $wuPath "TargetReleaseVersion"                 1
        Set-Reg $wuPath "TargetReleaseVersionInfo"             $curVer "String"
        Set-Reg $wuPath "DeferFeatureUpdates"                  1
        Set-Reg $wuPath "DeferFeatureUpdatesPeriodInDays"      365
        Set-Reg $wuPath "DeferQualityUpdates"                  0       # security still flows
        Write-OK "Feature Updates BLOCKED  Terkunci di versi $curVer (Build $curBld)"
        Write-OK "Security/quality updates tetap aktif"
    }

    "5" { # DRIVER AUDIT
        Write-Host ""
        Write-Step "AUDIT DRIVER TERPASANG"
        Write-Host ""
        Write-Host "  $($Global:DIM)$("DEVICE".PadRight(42)) $("VERSION".PadRight(18)) DATE$($Global:RESET)"
        Write-Separator "" $Global:DIM
        Get-WmiObject Win32_PnPSignedDriver |
            Where-Object { $_.DeviceName } |
            Sort-Object DeviceName |
            ForEach-Object {
                $date = "Unknown"
                if ($_.DriverDate) {
                    try { $date = ([System.Management.ManagementDateTimeConverter]::ToDateTime($_.DriverDate)).ToString("yyyy-MM-dd") }
                    catch {}
                }
                $name = $_.DeviceName.Substring(0,[Math]::Min(40,$_.DeviceName.Length))
                $ver  = if ($_.DriverVersion) { $_.DriverVersion } else { "N/A" }
                Write-Host "  $($Global:DIM)$($name.PadRight(42)) $($ver.PadRight(18)) $date$($Global:RESET)"
            }
        Write-OK "Audit selesai"
    }

	    "6" { # CLEAN OLD DRIVERS
	        Write-Host ""
	        Write-Step "BERSIHKAN DRIVER LAMA"
	        Write-Host ""
	        if (Confirm-NeoAction "  Hapus package driver yang tidak sedang dipakai? Buat restore point dulu." $false) {
	            $raw     = pnputil /enum-drivers 2>&1
	            $oemPkgs = ($raw | Select-String "oem\d+\.inf" -AllMatches).Matches | ForEach-Object { $_.Value } | Sort-Object -Unique
	            $cleaned = 0
	            foreach ($pkg in $oemPkgs) {
	                $result = pnputil /delete-driver $pkg 2>&1
	                if ($result -match "deleted|Deleted") {
	                    Write-OK "Removed orphaned: $pkg"
	                    $cleaned++
	                }
	            }
	            if ($cleaned -eq 0) { Write-Warn "Tidak ada orphaned driver packages" }
	            else { Write-OK "Total driver lama dihapus: $cleaned" }
	            # Driver Store size
	            $dsPath = "C:\Windows\System32\DriverStore\FileRepository"
	            $dsMB   = Get-FolderSizeMB $dsPath
	            Write-Info "Driver Store size sekarang: ${dsMB} MB"
	        } else {
	            Write-Skip "Clean old drivers"
	        }
	    }

    "7" { # WINGET
        Write-Host ""
        Write-Step "WINGET  SOFTWARE UPGRADE"
        Write-Host ""
        $wg = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $wg) {
            Write-Warn "winget tidak ditemukan. Install 'App Installer' dari Microsoft Store."
        } else {
            Write-Info "Daftar software yang perlu update:"
            Write-Host ""
            winget upgrade 2>&1 | ForEach-Object { Write-Host "  $($Global:DIM)$_$($Global:RESET)" }
            Write-Host ""
	            if (Confirm-NeoAction "  Upgrade SEMUA package?" $false) {
	                winget upgrade --all --accept-package-agreements --accept-source-agreements --silent 2>&1
	                Write-OK "Semua package di-upgrade"
            }
        }
    }

    "8" { # EXPORT HTML REPORT
        Write-Host ""
        Write-Step "EXPORT LAPORAN DRIVER (HTML)"
        Write-Host ""
        $reportPath = "$PSScriptRoot\..\reports\DriverReport_$(Get-Date -f 'yyyyMMdd_HHmmss').html"
        $rows = Get-WmiObject Win32_PnPSignedDriver |
            Where-Object { $_.DeviceName } |
            Sort-Object DeviceName |
            ForEach-Object {
                $date = "Unknown"
                if ($_.DriverDate) {
                    try { $date = ([System.Management.ManagementDateTimeConverter]::ToDateTime($_.DriverDate)).ToString("yyyy-MM-dd") }
                    catch {}
                }
	                $device = ConvertTo-HtmlSafe $_.DeviceName
	                $version = ConvertTo-HtmlSafe $_.DriverVersion
	                $manufacturer = ConvertTo-HtmlSafe $_.Manufacturer
	                "<tr><td>$device</td><td>$version</td><td>$date</td><td>$manufacturer</td></tr>"
	            }

        $table = @"
<div class='card'>
<h2> Installed Drivers</h2>
<table style='width:100%;border-collapse:collapse;font-size:.8rem'>
<thead><tr style='background:#21262d'>
<th style='padding:.5rem;text-align:left'>Device</th>
<th style='padding:.5rem;text-align:left'>Version</th>
<th style='padding:.5rem;text-align:left'>Date</th>
<th style='padding:.5rem;text-align:left'>Manufacturer</th>
</tr></thead>
<tbody>$($rows -join '')</tbody>
</table>
</div>
"@
        if (-not (Test-Path "$PSScriptRoot\..\reports")) {
            New-Item -Path "$PSScriptRoot\..\reports" -ItemType Directory -Force | Out-Null
        }
        if (Export-HtmlReport "Driver Audit Report" $table $reportPath) {
            Write-OK "Laporan: $reportPath"
            Start-Process $reportPath -ErrorAction SilentlyContinue
        } else {
            Write-Err "Gagal export laporan"
        }
    }

	    "9" { # RESTORE DEFAULTS
	        Write-Host ""
	        Write-Step "RESTORE UPDATE SETTINGS"
	        Write-Host ""
	        Backup-RegKey "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" | Out-Null
	        Remove-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Recurse -Force -ErrorAction SilentlyContinue
	        Set-Service wuauserv -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service wuauserv -ErrorAction SilentlyContinue
        Set-Reg "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "PauseUpdatesExpiryTime" "" "String"
        Write-OK "Windows Update dikembalikan ke default"
    }

	    "0" { # SAFE PRESET
	        Write-Host ""
	        Write-Step "PRESET UPDATE AMAN (MANUAL + BLOCK FEATURE)"
	        Write-Host ""
	        $wuAU = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
	        Set-Reg $wuAU "NoAutoUpdate"                   1
	        Set-Reg $wuAU "AUOptions"                      2
	        Set-Reg $wuAU "NoAutoRebootWithLoggedOnUsers"  1
	        Set-Reg $wuAU "RebootWarningTimeoutEnabled"    1
	        Set-Reg $wuAU "RebootWarningTimeout"           240
	        Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" 0

	        $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
	        $curVer = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion
	        $curBld = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
	        Set-Reg $wuPath "TargetReleaseVersion"                 1
	        Set-Reg $wuPath "TargetReleaseVersionInfo"             $curVer "String"
	        Set-Reg $wuPath "DeferFeatureUpdates"                  1
	        Set-Reg $wuPath "DeferFeatureUpdatesPeriodInDays"      365
	        Set-Reg $wuPath "DeferQualityUpdates"                  0
	        Write-OK "Preset aman diterapkan: update notify-only, no auto-restart, feature update terkunci di $curVer (Build $curBld)"
	        Write-Skip "Pause 35 hari dan hapus driver lama"
	    }
	}

#  Update Status Summary 
Write-Host ""
Write-Step "WINDOWS UPDATE STATUS"
Write-Host ""
$wuSvc = Get-Service wuauserv -ErrorAction SilentlyContinue
if ($wuSvc) {
    $color = if ($wuSvc.Status -eq "Running") { $Global:GREEN } else { $Global:DIM }
    $wuStart = (Get-CimInstance Win32_Service -Filter "Name='wuauserv'" -ErrorAction SilentlyContinue).StartMode
    Write-Host "  Windows Update Service: ${color}$($wuSvc.Status)$($Global:RESET) [$wuStart]"
}
$pauseKey = Get-RegValue "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "PauseUpdatesExpiryTime" ""
if ($pauseKey) { Write-Host "  Update paused until: $($Global:YELLOW)$pauseKey$($Global:RESET)" }

Write-Host ""
Write-Separator "" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)   UPDATE & DRIVER MANAGER SELESAI$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
