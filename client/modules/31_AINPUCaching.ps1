#Requires -RunAsAdministrator
<# MODULE 31 - AI AND NPU CACHING LIMITS #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "31" "AI" "AI & NPU CACHING LIMITS"

function Get-NeoPathSizeMB {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return 0 }
    return Get-FolderSizeMB $Path
}

$npuDevices = @(Get-PnpDevice | Where-Object { $_.FriendlyName -match "NPU|Neural|AI|VPU|Movidius|Hexagon|Ryzen AI|Intel\(R\) AI|Qualcomm" } | Select-Object Class, FriendlyName, Status, InstanceId)
$gpuDevices = @(Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, AdapterRAM, VideoProcessor)
$cs = Get-CimInstance Win32_ComputerSystem
$pageFiles = @(Get-CimInstance Win32_PageFileUsage | Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage)

$cacheRoots = @(
    [PSCustomObject]@{ Name="HuggingFace"; Path=(Join-Path $env:USERPROFILE ".cache\huggingface"); RecommendedLimitGB=20 },
    [PSCustomObject]@{ Name="OllamaModels"; Path=(Join-Path $env:USERPROFILE ".ollama\models"); RecommendedLimitGB=80 },
    [PSCustomObject]@{ Name="PipCache"; Path=(Join-Path $env:LOCALAPPDATA "pip\Cache"); RecommendedLimitGB=5 },
    [PSCustomObject]@{ Name="NvidiaDXCache"; Path=(Join-Path $env:LOCALAPPDATA "NVIDIA\DXCache"); RecommendedLimitGB=5 },
    [PSCustomObject]@{ Name="D3DSCache"; Path=(Join-Path $env:LOCALAPPDATA "D3DSCache"); RecommendedLimitGB=5 }
)

$cacheReport = @($cacheRoots | ForEach-Object {
    [PSCustomObject]@{
        name = $_.Name
        path = $_.Path
        exists = [bool](Test-Path $_.Path)
        size_mb = Get-NeoPathSizeMB $_.Path
        recommended_limit_gb = $_.RecommendedLimitGB
    }
})

$report = [PSCustomObject]@{
    captured_at = (Get-Date).ToString("o")
    ram_gb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    logical_processors = $cs.NumberOfLogicalProcessors
    npu_devices = $npuDevices
    gpu_devices = $gpuDevices
    page_files = $pageFiles
    caches = $cacheReport
}

Write-Step "AI ACCELERATOR INVENTORY"
Write-Host ""
if ($npuDevices.Count -gt 0) {
    foreach ($device in $npuDevices) {
        Write-Info ("NPU candidate: {0} [{1}]" -f $device.FriendlyName, $device.Status)
    }
} else {
    Write-Info "No dedicated NPU device detected by PnP name. GPU/CPU acceleration may still be available."
}

Write-Host ""
Write-Step "CACHE INVENTORY"
Write-Host ""
foreach ($cache in $cacheReport) {
    Write-Host ("  {0,-16} {1,8} MB  limit={2} GB  {3}" -f $cache.name, $cache.size_mb, $cache.recommended_limit_gb, $cache.path)
}

$dir = Join-Path $Global:LogDir "ai"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$path = Join-Path $dir ("ai-npu-cache_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
Write-OK "AI/NPU cache report: $path"

if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) {
    Write-Warn "Non-interactive mode: audit only."
    Wait-AnyKey
    return
}

Write-Host ""
Write-Host "  [1] Audit only"
Write-Host "  [2] Write NeoOptimize AI cache limit policy"
Write-Host ""
$choice = Read-NeoChoice "  Pilihan [1-2]" @("1","2") "1"

if ($choice -eq "2" -and (Confirm-NeoAction "Write local NeoOptimize AI cache policy file? This does not delete model files." $false)) {
    $configPath = Join-Path $Global:NeoOptimizeRoot "config\NeoOptimize.AICacheLimits.json"
    $policy = [PSCustomObject]@{
        schema_version = "1.0"
        updated_at = (Get-Date).ToString("o")
        cache_limits = $cacheReport | Select-Object name, path, recommended_limit_gb
        note = "NeoOptimize policy only; model runtimes must opt in before enforcing limits."
    }
    $policy | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath -Encoding UTF8
    Write-OK "AI cache policy written: $configPath"
}

Write-Footer
Wait-AnyKey
