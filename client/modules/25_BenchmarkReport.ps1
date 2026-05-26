#Requires -RunAsAdministrator
<# MODULE 25 - BEFORE/AFTER BENCHMARK REPORT #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "25" "BENCH" "BEFORE/AFTER BENCHMARK REPORT"

$dir = Join-Path $Global:LogDir "benchmark"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }

function Get-NeoCounterValue {
    param([string]$CounterPath)
    try {
        $sample = Get-Counter -Counter $CounterPath -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop
        $value = ($sample.CounterSamples | Select-Object -First 1).CookedValue
        return [math]::Round([double]$value, 2)
    } catch {
        return $null
    }
}

function New-NeoBenchmarkSnapshot {
    param([string]$Phase = "snapshot")
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $topCpu = @(Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, Id, CPU, WorkingSet)
    $topRam = @(Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 10 Name, Id, CPU, WorkingSet)

    return [PSCustomObject]@{
        phase = $Phase
        captured_at = (Get-Date).ToString("o")
        uptime_seconds = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalSeconds, 0)
        cpu_percent = Get-NeoCounterValue "\Processor(_Total)\% Processor Time"
        memory_available_mb = [math]::Round($os.FreePhysicalMemory / 1024, 0)
        memory_committed_percent = Get-NeoCounterValue "\Memory\% Committed Bytes In Use"
        disk_c_percent_idle = Get-NeoCounterValue "\LogicalDisk(C:)\% Idle Time"
        disk_c_queue = Get-NeoCounterValue "\LogicalDisk(C:)\Current Disk Queue Length"
        system_processes = @(Get-Process).Count
        services_running = @(Get-Service | Where-Object { $_.Status -eq "Running" }).Count
        computer = [PSCustomObject]@{
            manufacturer = $cs.Manufacturer
            model = $cs.Model
            ram_gb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
            logical_processors = $cs.NumberOfLogicalProcessors
        }
        top_cpu = $topCpu
        top_ram = $topRam
    }
}

function Compare-NeoBenchmark {
    param($Before, $After)
    if ($null -eq $Before -or $null -eq $After) { return $null }
    return [PSCustomObject]@{
        baseline_file = $Before.__file
        after_file = $After.__file
        cpu_percent_delta = if ($null -ne $Before.cpu_percent -and $null -ne $After.cpu_percent) { [math]::Round($After.cpu_percent - $Before.cpu_percent, 2) } else { $null }
        memory_available_mb_delta = [math]::Round($After.memory_available_mb - $Before.memory_available_mb, 0)
        process_count_delta = [int]$After.system_processes - [int]$Before.system_processes
        services_running_delta = [int]$After.services_running - [int]$Before.services_running
        disk_queue_delta = if ($null -ne $Before.disk_c_queue -and $null -ne $After.disk_c_queue) { [math]::Round($After.disk_c_queue - $Before.disk_c_queue, 2) } else { $null }
    }
}

if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) {
    $choice = "1"
} else {
    Write-Host ""
    Write-Host "  [1] Capture benchmark snapshot"
    Write-Host "  [2] Capture after snapshot and compare with previous"
    Write-Host ""
    $choice = Read-NeoChoice "  Pilihan [1-2]" @("1","2") "1"
}

$phase = if ($choice -eq "2") { "after" } else { "baseline" }
$snapshot = New-NeoBenchmarkSnapshot -Phase $phase
$path = Join-Path $dir ("benchmark_{0}_{1}.json" -f $phase, (Get-Date -Format "yyyyMMdd_HHmmss"))
$snapshot | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
Write-OK "Benchmark snapshot: $path"

if ($choice -eq "2") {
    $previousFile = Get-ChildItem -Path $dir -Filter "benchmark_baseline_*.json" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($previousFile) {
        $before = Get-Content -Path $previousFile.FullName -Raw | ConvertFrom-Json
        $after = Get-Content -Path $path -Raw | ConvertFrom-Json
        $before | Add-Member -NotePropertyName "__file" -NotePropertyValue $previousFile.FullName -Force
        $after | Add-Member -NotePropertyName "__file" -NotePropertyValue $path -Force
        $comparison = Compare-NeoBenchmark -Before $before -After $after
        $comparePath = Join-Path $dir ("benchmark_compare_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
        $comparison | ConvertTo-Json -Depth 6 | Set-Content -Path $comparePath -Encoding UTF8
        Write-Step "COMPARISON"
        Write-Host ""
        Write-Info ("Memory available delta : {0} MB" -f $comparison.memory_available_mb_delta)
        Write-Info ("Process count delta    : {0}" -f $comparison.process_count_delta)
        Write-Info ("Running services delta : {0}" -f $comparison.services_running_delta)
        Write-OK "Comparison report: $comparePath"
    } else {
        Write-Warn "No baseline snapshot found. Run option 1 before optimization, then option 2 after optimization."
    }
}

Write-Footer
Wait-AnyKey
