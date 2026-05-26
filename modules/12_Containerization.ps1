#Requires -RunAsAdministrator
<# MODULE 12 - CONTAINERIZATION & WSL OPTIMIZER #>
param([switch]$Enforce)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "12" "WSL" "CONTAINERIZATION (WSL & HYPER-V)"

$changes = 0
$canApply = [bool]$Enforce -or [bool]$Global:NeoOptimizeConfirmAll

function Invoke-ContainerChange {
    param(
        [string]$Prompt,
        [scriptblock]$Action
    )
    if ($canApply -or (Confirm-NeoAction $Prompt $false)) {
        & $Action
        return $true
    }
    Write-Skip $Prompt
    return $false
}

Write-Step "WSL STATUS"
Write-Host ""
if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
    $wslStatus = wsl.exe --status 2>&1
    if ($wslStatus) { $wslStatus | ForEach-Object { Write-Info $_ } }
} else {
    Write-Info "wsl.exe tidak tersedia."
}

$cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
$ramGB = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB) } else { 8 }
$cpuCount = if ($cpu) { [int]$cpu.NumberOfLogicalProcessors } else { 4 }
$wslMem = [math]::Max(2, [math]::Min([math]::Floor($ramGB / 2), 16))
$wslCpu = [math]::Max(2, [math]::Floor($cpuCount / 2))
$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
$wslConfigContent = @"
[wsl2]
memory=${wslMem}GB
processors=${wslCpu}
swap=2GB
localhostForwarding=true
guiApplications=false

[experimental]
autoMemoryReclaim=dropcache
sparseVhd=true
"@

Write-Host ""
Write-Step "WSLCONFIG PLAN"
Write-Host ""
Write-Info "Target file: $wslConfigPath"
Write-Info "Recommended limits: memory=${wslMem}GB processors=${wslCpu} swap=2GB"
if (Test-Path $wslConfigPath) {
    Write-Info "Existing .wslconfig detected and will be backed up before any write."
} else {
    Write-Info "No existing .wslconfig found."
}

if (Invoke-ContainerChange "Write/update .wslconfig with conservative WSL2 resource limits?" {
    Backup-File $wslConfigPath ".wslconfig" | Out-Null
    Set-Content -Path $wslConfigPath -Value $wslConfigContent -Encoding ASCII -Force
    Write-OK "WSL2 config updated. Run 'wsl --shutdown' manually when ready."
}) {
    $changes++
}

Write-Host ""
Write-Step "HYPER-V VIRTUAL ADAPTERS"
Write-Host ""
$vAdapters = Get-NetAdapter -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceDescription -match "Hyper-V Virtual Ethernet" }
if ($vAdapters) {
    foreach ($adapter in $vAdapters) {
        Write-Info ("{0}: {1}" -f $adapter.Name, $adapter.Status)
    }
} else {
    Write-Info "Tidak ada Hyper-V virtual Ethernet adapter yang terdeteksi."
}
Write-Warn "Adapter Hyper-V/WSL tidak dinonaktifkan otomatis agar Docker, WSL, dan VM tidak putus."

Write-Host ""
Write-Step "VMMS PRIORITY"
Write-Host ""
$vmms = Get-Process vmms -ErrorAction SilentlyContinue
if ($vmms) {
    Write-Info "vmms.exe running. Priority: $($vmms.PriorityClass)"
} else {
    Write-Skip "vmms.exe"
}
Write-Info "NeoOptimize tidak mengubah prioritas vmms.exe secara otomatis."

Write-Host ""
Write-Separator "=" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)CONTAINERIZATION AUDIT SELESAI - $changes perubahan diterapkan$($Global:RESET)"
Write-Host ""
Write-Footer
Wait-AnyKey
