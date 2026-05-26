#Requires -RunAsAdministrator
<# MODULE 22 - WINDOWS FEATURE OPTIMIZER #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "22" "FEAT" "WINDOWS FEATURE OPTIMIZER"

$features = @(
    [PSCustomObject]@{ Name="SMB1Protocol"; Label="SMBv1 legacy protocol"; RecommendedDisable=$true },
    [PSCustomObject]@{ Name="MicrosoftWindowsPowerShellV2Root"; Label="PowerShell 2.0 engine"; RecommendedDisable=$true },
    [PSCustomObject]@{ Name="Printing-XPSServices-Features"; Label="XPS print services"; RecommendedDisable=$false },
    [PSCustomObject]@{ Name="WorkFolders-Client"; Label="Work Folders client"; RecommendedDisable=$false },
    [PSCustomObject]@{ Name="TelnetClient"; Label="Telnet client"; RecommendedDisable=$true },
    [PSCustomObject]@{ Name="TFTP"; Label="TFTP client"; RecommendedDisable=$true }
)

Write-Step "OPTIONAL FEATURE STATUS"
Write-Host ""
$available = New-Object System.Collections.Generic.List[object]
foreach ($feature in $features) {
    $state = Get-WindowsOptionalFeature -Online -FeatureName $feature.Name -ErrorAction SilentlyContinue
    if ($state) {
        $row = [PSCustomObject]@{
            Name = $feature.Name
            Label = $feature.Label
            State = $state.State
            RecommendedDisable = [bool]$feature.RecommendedDisable
        }
        $available.Add($row) | Out-Null
        Write-Host ("  {0,-34} {1,-10} {2}" -f $row.Name, $row.State, $row.Label)
    }
}

$dir = Join-Path $Global:LogDir "features"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$reportPath = Join-Path $dir ("windows-features_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$available | ConvertTo-Json -Depth 4 | Set-Content -Path $reportPath -Encoding UTF8
Write-OK "Feature report: $reportPath"

if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) {
    Write-Warn "Non-interactive mode: audit only."
    Wait-AnyKey
    return
}

Write-Host ""
Write-Host "  [1] Audit only"
Write-Host "  [2] Disable recommended legacy features"
Write-Host ""
$choice = Read-NeoChoice "  Pilihan [1-2]" @("1","2") "1"
if ($choice -eq "2") {
    $targets = @($available | Where-Object { $_.RecommendedDisable -and $_.State -eq "Enabled" })
    if ($targets.Count -eq 0) {
        Write-OK "Tidak ada recommended legacy feature aktif."
    } elseif (Confirm-NeoAction "Disable recommended legacy optional features? Restart may be required." $false) {
        foreach ($target in $targets) {
            Disable-WindowsOptionalFeature -Online -FeatureName $target.Name -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-OK "Disable requested: $($target.Name)"
        }
    }
}

Write-Host ""
Write-Separator "=" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)WINDOWS FEATURE OPTIMIZER SELESAI$($Global:RESET)"
Write-Footer
Wait-AnyKey
