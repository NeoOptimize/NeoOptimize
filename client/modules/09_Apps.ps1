#Requires -RunAsAdministrator
<#
.SYNOPSIS
    NeoOptimize - Selectable Windows App Debloater
.DESCRIPTION
    Audits installed AppX packages and removes only user-selected debloat
    candidates. Camera, Microphone, Location, Store, Photos, Calculator, App
    Installer, Security UI, and Terminal are protected from removal.
#>

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "09" "APP" "SELECTABLE APP & DEBLOAT MANAGER"

$protectedPatterns = @(
    "Microsoft.WindowsCamera",
    "Microsoft.Windows.Photos",
    "Microsoft.WindowsStore",
    "Microsoft.StorePurchaseApp",
    "Microsoft.DesktopAppInstaller",
    "Microsoft.WindowsCalculator",
    "Microsoft.WindowsTerminal",
    "Microsoft.SecHealthUI",
    "Microsoft.MicrosoftEdge.Stable"
)

$catalog = @(
    [PSCustomObject]@{ Id=1;  Label="Bing News";             Pattern="Microsoft.BingNews";                         Group="Consumer"; Recommended=$true },
    [PSCustomObject]@{ Id=2;  Label="Bing Weather";          Pattern="Microsoft.BingWeather";                      Group="Consumer"; Recommended=$true },
    [PSCustomObject]@{ Id=3;  Label="Get Started";           Pattern="Microsoft.Getstarted";                       Group="Consumer"; Recommended=$true },
    [PSCustomObject]@{ Id=4;  Label="Feedback Hub";          Pattern="Microsoft.WindowsFeedbackHub";               Group="Consumer"; Recommended=$true },
    [PSCustomObject]@{ Id=5;  Label="Solitaire";             Pattern="Microsoft.MicrosoftSolitaireCollection";     Group="Games";    Recommended=$true },
    [PSCustomObject]@{ Id=6;  Label="Mixed Reality Portal";  Pattern="Microsoft.MixedReality.Portal";              Group="XR";       Recommended=$true },
    [PSCustomObject]@{ Id=7;  Label="People";                Pattern="Microsoft.People";                           Group="Consumer"; Recommended=$true },
    [PSCustomObject]@{ Id=8;  Label="Skype";                 Pattern="Microsoft.SkypeApp";                         Group="Consumer"; Recommended=$true },
    [PSCustomObject]@{ Id=9;  Label="Windows Maps";          Pattern="Microsoft.WindowsMaps";                      Group="Consumer"; Recommended=$true },
    [PSCustomObject]@{ Id=10; Label="Media Player Music";    Pattern="Microsoft.ZuneMusic";                        Group="Media";    Recommended=$true },
    [PSCustomObject]@{ Id=11; Label="Movies & TV";           Pattern="Microsoft.ZuneVideo";                        Group="Media";    Recommended=$true },
    [PSCustomObject]@{ Id=12; Label="Phone Link";            Pattern="Microsoft.YourPhone";                        Group="Consumer"; Recommended=$false },
    [PSCustomObject]@{ Id=13; Label="Microsoft To Do";       Pattern="Microsoft.Todos";                            Group="Consumer"; Recommended=$false },
    [PSCustomObject]@{ Id=14; Label="Cortana";               Pattern="Microsoft.549981C3F5F10";                    Group="AI";       Recommended=$true },
    [PSCustomObject]@{ Id=15; Label="Consumer Teams";        Pattern="MicrosoftTeams";                             Group="Consumer"; Recommended=$true },
    [PSCustomObject]@{ Id=16; Label="Clipchamp";             Pattern="Clipchamp.Clipchamp";                        Group="Media";    Recommended=$false },
    [PSCustomObject]@{ Id=17; Label="Xbox App";              Pattern="Microsoft.XboxApp";                          Group="Xbox";     Recommended=$false },
    [PSCustomObject]@{ Id=18; Label="Xbox Gaming App";       Pattern="Microsoft.GamingApp";                        Group="Xbox";     Recommended=$false },
    [PSCustomObject]@{ Id=19; Label="Xbox Game Overlay";     Pattern="Microsoft.XboxGameOverlay";                  Group="Xbox";     Recommended=$false },
    [PSCustomObject]@{ Id=20; Label="Xbox Gaming Overlay";   Pattern="Microsoft.XboxGamingOverlay";                Group="Xbox";     Recommended=$false },
    [PSCustomObject]@{ Id=21; Label="Xbox Identity Provider";Pattern="Microsoft.XboxIdentityProvider";             Group="Xbox";     Recommended=$false },
    [PSCustomObject]@{ Id=22; Label="Xbox Speech Overlay";   Pattern="Microsoft.XboxSpeechToTextOverlay";          Group="Xbox";     Recommended=$false },
    [PSCustomObject]@{ Id=23; Label="Xbox TCUI";             Pattern="Microsoft.Xbox.TCUI";                        Group="Xbox";     Recommended=$false }
)

function Test-ProtectedAppPattern {
    param([string]$Name)
    foreach ($pattern in $protectedPatterns) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

function Get-DebloatInventory {
    $packages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($item in $catalog) {
        $matches = @($packages | Where-Object { $_.Name -like $item.Pattern })
        $rows.Add([PSCustomObject]@{
            Id = $item.Id
            Label = $item.Label
            Pattern = $item.Pattern
            Group = $item.Group
            Recommended = [bool]$item.Recommended
            Installed = ($matches.Count -gt 0)
            PackageCount = $matches.Count
            PackageNames = (($matches | Select-Object -ExpandProperty Name -Unique) -join ", ")
        }) | Out-Null
    }
    return @($rows)
}

function Remove-DebloatPattern {
    param([string]$Pattern)

    if (Test-ProtectedAppPattern $Pattern) {
        Write-Warn "Protected package skipped: $Pattern"
        return 0
    }

    $removed = 0
    $packages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $Pattern })
    foreach ($pkg in $packages) {
        if (Test-ProtectedAppPattern $pkg.Name) {
            Write-Warn "Protected package skipped: $($pkg.Name)"
            continue
        }
        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            Write-OK "Removed AppX: $($pkg.Name)"
            $removed++
        } catch {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                Write-OK "Removed AppX for current user: $($pkg.Name)"
                $removed++
            } catch {
                Write-Warn "Failed to remove $($pkg.Name): $($_.Exception.Message)"
            }
        }
    }

    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $Pattern })
    foreach ($pkg in $provisioned) {
        if (Test-ProtectedAppPattern $pkg.DisplayName) {
            Write-Warn "Protected provisioned package skipped: $($pkg.DisplayName)"
            continue
        }
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction Stop | Out-Null
            Write-OK "Removed provisioned AppX: $($pkg.DisplayName)"
            $removed++
        } catch {
            Write-Warn "Failed to remove provisioned $($pkg.DisplayName): $($_.Exception.Message)"
        }
    }

    return $removed
}

function Export-DebloatInventory {
    param($Inventory)
    $dir = Join-Path $Global:LogDir "apps"
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $path = Join-Path $dir ("debloat-inventory_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $Inventory | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    Write-OK "Inventory report: $path"
}

function Restore-CoreApps {
    $corePatterns = @(
        "Microsoft.WindowsCamera",
        "Microsoft.Windows.Photos",
        "Microsoft.WindowsStore",
        "Microsoft.StorePurchaseApp",
        "Microsoft.DesktopAppInstaller",
        "Microsoft.WindowsCalculator"
    )
    $count = 0
    foreach ($pattern in $corePatterns) {
        Get-AppxPackage -AllUsers -Name $pattern -ErrorAction SilentlyContinue | ForEach-Object {
            $manifest = Join-Path $_.InstallLocation "AppXManifest.xml"
            if (Test-Path $manifest) {
                try {
                    Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
                    Write-OK "Re-registered: $($_.Name)"
                    $count++
                } catch {
                    Write-Warn "Failed to re-register $($_.Name): $($_.Exception.Message)"
                }
            }
        }
    }
    return $count
}

$inventory = Get-DebloatInventory
Write-Step "INSTALLED DEBLOAT CANDIDATES"
Write-Host ""
foreach ($row in $inventory) {
    $status = if ($row.Installed) { "installed" } else { "not installed" }
    $rec = if ($row.Recommended) { "recommended" } else { "optional" }
    Write-Host ("  [{0,2}] {1,-28} {2,-10} {3,-12} {4}" -f $row.Id, $row.Label, $row.Group, $status, $rec)
}
Export-DebloatInventory $inventory

Write-Host ""
Write-Step "PROTECTED CORE APPS"
Write-Host ""
Write-Info "Protected: Camera, Photos, Store, StorePurchase, App Installer, Calculator, Terminal, Security UI, Edge."
Write-Info "Camera/Microphone/Location permissions are not managed here and remain user-controlled."

if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) {
    Write-Warn "Non-interactive mode: audit only, no app removal."
    Wait-AnyKey
    return
}

Write-Host ""
Write-Host "  [1] Audit only"
Write-Host "  [2] Remove recommended consumer bloat"
Write-Host "  [3] Remove Xbox packages only"
Write-Host "  [4] Select packages by number"
Write-Host "  [5] Disable OneDrive autostart only"
Write-Host "  [6] Re-register protected core apps"
Write-Host ""
$choice = Read-NeoChoice "  Pilihan [1-6]" @("1","2","3","4","5","6") "1"

$targets = @()
switch ($choice) {
    "1" {
        Write-Info "Audit only selesai. Tidak ada aplikasi dihapus."
    }
    "2" {
        $targets = @($catalog | Where-Object { $_.Recommended })
    }
    "3" {
        $targets = @($catalog | Where-Object { $_.Group -eq "Xbox" })
    }
    "4" {
        $raw = Read-Host "  Masukkan nomor paket dipisah koma, contoh: 1,4,10"
        $ids = @($raw -split "," | ForEach-Object { [int]($_.Trim()) } | Where-Object { $_ -gt 0 })
        $targets = @($catalog | Where-Object { $ids -contains $_.Id })
    }
    "5" {
        Backup-RegKey "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" | Out-Null
        Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue
        Write-OK "OneDrive autostart disabled for current user. OneDrive is not uninstalled."
    }
    "6" {
        $restored = Restore-CoreApps
        Write-OK "Core app re-register completed: $restored app(s)."
    }
}

if ($targets.Count -gt 0) {
    Write-Warn "Selected packages will be removed for all users when Windows allows it."
    if (Confirm-NeoAction "Proceed with selected AppX removal?" $false) {
        $removed = 0
        foreach ($target in $targets) {
            $removed += Remove-DebloatPattern $target.Pattern
        }
        Write-OK "Debloat removal completed: $removed package action(s)."
    } else {
        Write-Info "Debloat removal cancelled."
    }
}

Write-Host ""
Write-Separator "=" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)APP MANAGER SELESAI$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
