#Requires -RunAsAdministrator
<# MODULE 28 - CONTAINERIZATION AND HYPER-V TUNING #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "28" "HV" "CONTAINERIZATION & HYPER-V TUNING"

function Get-NeoOptionalFeatureState {
    param([string]$Name)
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $Name
    if ($feature) { return $feature.State }
    return "Unavailable"
}

$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
$wslConfig = if (Test-Path $wslConfigPath) { Get-Content -Path $wslConfigPath -Raw } else { "" }

$report = [PSCustomObject]@{
    captured_at = (Get-Date).ToString("o")
    hypervisor_present = $cs.HypervisorPresent
    virtualization_firmware_enabled = $cpu.VirtualizationFirmwareEnabled
    slat = $cpu.SecondLevelAddressTranslationExtensions
    features = [PSCustomObject]@{
        hyper_v = Get-NeoOptionalFeatureState "Microsoft-Hyper-V-All"
        virtual_machine_platform = Get-NeoOptionalFeatureState "VirtualMachinePlatform"
        wsl = Get-NeoOptionalFeatureState "Microsoft-Windows-Subsystem-Linux"
        containers = Get-NeoOptionalFeatureState "Containers"
    }
    vethernet = @(Get-NetAdapter | Where-Object { $_.Name -like "vEthernet*" } | Select-Object Name, Status, LinkSpeed, InterfaceDescription)
    wsl_status = (& wsl.exe --status 2>&1)
    wsl_config_path = $wslConfigPath
    wsl_config_present = [bool](Test-Path $wslConfigPath)
}

Write-Step "VIRTUALIZATION STATUS"
Write-Host ""
Write-Info ("Hypervisor present          : {0}" -f $report.hypervisor_present)
Write-Info ("Firmware virtualization     : {0}" -f $report.virtualization_firmware_enabled)
Write-Info ("SLAT support                : {0}" -f $report.slat)
Write-Info ("Hyper-V optional feature    : {0}" -f $report.features.hyper_v)
Write-Info ("Virtual Machine Platform    : {0}" -f $report.features.virtual_machine_platform)
Write-Info ("WSL optional feature        : {0}" -f $report.features.wsl)
Write-Info ("Containers optional feature : {0}" -f $report.features.containers)

Write-Host ""
Write-Step "VIRTUAL NETWORK ADAPTERS"
Write-Host ""
foreach ($adapter in $report.vethernet) {
    Write-Host ("  {0,-28} {1,-10} {2}" -f $adapter.Name, $adapter.Status, $adapter.LinkSpeed)
}
if ($report.vethernet.Count -eq 0) { Write-Info "No vEthernet adapters detected." }

$dir = Join-Path $Global:LogDir "container"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$path = Join-Path $dir ("container-hyperv_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
Write-OK "Container/Hyper-V report: $path"

if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) {
    Write-Warn "Non-interactive mode: audit only."
    Wait-AnyKey
    return
}

Write-Host ""
Write-Host "  [1] Audit only"
Write-Host "  [2] Write safe WSL2 .wslconfig memory policy"
Write-Host "  [3] Write WSL2 policy and run wsl --shutdown"
Write-Host ""
$choice = Read-NeoChoice "  Pilihan [1-3]" @("1","2","3") "1"

if ($choice -in @("2","3")) {
    $ramGb = [math]::Max(4, [math]::Floor(($cs.TotalPhysicalMemory / 1GB) * 0.50))
    $processors = [math]::Max(2, [math]::Floor([double]$cs.NumberOfLogicalProcessors * 0.75))
    $swapGb = [math]::Max(2, [math]::Floor($ramGb / 4))
    $newConfig = @"
[wsl2]
memory=${ramGb}GB
processors=$processors
swap=${swapGb}GB
autoMemoryReclaim=dropCache
localhostForwarding=true
"@
    if (Confirm-NeoAction "Write .wslconfig with memory=${ramGb}GB processors=$processors swap=${swapGb}GB?" $false) {
        if (Test-Path $wslConfigPath) {
            $backup = Join-Path $dir (".wslconfig_backup_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
            Copy-Item -Path $wslConfigPath -Destination $backup -Force
            Write-OK "Existing .wslconfig backup: $backup"
        }
        $newConfig | Set-Content -Path $wslConfigPath -Encoding ASCII
        Write-OK "Wrote WSL2 policy: $wslConfigPath"
        if ($choice -eq "3" -and (Confirm-NeoAction "Run wsl --shutdown to reload WSL2 policy?" $false)) {
            & wsl.exe --shutdown
            Write-OK "WSL shutdown requested."
        }
    }
}

Write-Footer
Wait-AnyKey
