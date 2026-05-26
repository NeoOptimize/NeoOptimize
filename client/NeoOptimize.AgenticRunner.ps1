#Requires -Version 5.1
<#
.SYNOPSIS
    NEO Agentic Runtime for NeoOptimize.

.DESCRIPTION
    Safety-bound observe -> diagnose -> plan -> approve -> act -> verify loop.
    NEO can read local Windows state, write reports/memory, and run allowlisted
    NeoOptimize actions only through explicit operator approval.
#>

[CmdletBinding()]
param(
    [ValidateSet("Plan", "RunOnce", "Loop", "Status")]
    [string]$Mode = "Plan",
    [string]$Goal = "optimize and maintain this Windows system safely",
    [int]$MaxActions = 3,
    [int]$IntervalSeconds = 300,
    [switch]$Execute,
    [switch]$AssumeYes,
    [switch]$NoOpen
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:PolicyPath = Join-Path $Script:Root "config\NeoOptimize.AgenticPolicy.json"
$Script:OperatorPolicyPath = Join-Path $Script:Root "config\NeoOptimize.OperatorPolicy.json"
$Script:ReportsDir = Join-Path $Script:Root "reports\agentic"
$Script:EnginePath = Join-Path $Script:Root "NeoOptimize.ps1"

if (-not (Test-Path $Script:ReportsDir)) {
    New-Item -Path $Script:ReportsDir -ItemType Directory -Force | Out-Null
}

function Read-NeoJsonFile {
    param([string]$Path, [object]$Fallback)
    try {
        if (Test-Path $Path) { return (Get-Content -Path $Path -Raw | ConvertFrom-Json) }
    } catch {}
    return $Fallback
}

function Get-NeoAgenticPolicy {
    $fallback = [PSCustomObject]@{
        default_mode = "observe_plan_confirm_act_verify"
        autonomous_execution = $false
        approval = [PSCustomObject]@{ require_confirmation_for_all_actions = $true }
        action_lanes = @()
    }
    return Read-NeoJsonFile -Path $Script:PolicyPath -Fallback $fallback
}

function Get-NeoAgenticSnapshot {
    $os = $null
    $cpu = $null
    $disk = $null
    $defender = $null
    try { $os = Get-CimInstance Win32_OperatingSystem } catch {}
    try { $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 } catch {}
    try { $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" } catch {}
    try { $defender = Get-MpComputerStatus } catch {}

    $ramUsedPct = $null
    if ($os -and [double]$os.TotalVisibleMemorySize -gt 0) {
        $ramUsedPct = [math]::Round(((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100), 1)
    }
    $diskFreePct = $null
    if ($disk -and [double]$disk.Size -gt 0) {
        $diskFreePct = [math]::Round((($disk.FreeSpace / $disk.Size) * 100), 1)
    }

    $criticalEvents = 0
    $errorEvents = 0
    try {
        $since = (Get-Date).AddHours(-24)
        $events = Get-WinEvent -FilterHashtable @{ LogName = "System"; StartTime = $since; Level = 1,2 } -MaxEvents 80
        $criticalEvents = @($events | Where-Object { $_.Level -eq 1 }).Count
        $errorEvents = @($events | Where-Object { $_.Level -eq 2 }).Count
    } catch {}

    $pendingReboot = $false
    foreach ($key in @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )) {
        if (Test-Path $key) { $pendingReboot = $true }
    }

    [PSCustomObject]@{
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        computer_name = $env:COMPUTERNAME
        os = if ($os) { $os.Caption } else { "Windows" }
        build = if ($os) { $os.BuildNumber } else { "" }
        cpu = if ($cpu) { $cpu.Name } else { "" }
        cpu_load_pct = if ($cpu -and $null -ne $cpu.LoadPercentage) { [int]$cpu.LoadPercentage } else { $null }
        ram_used_pct = $ramUsedPct
        disk_c_free_pct = $diskFreePct
        disk_c_free_gb = if ($disk) { [math]::Round(($disk.FreeSpace / 1GB), 2) } else { $null }
        defender_realtime = if ($defender) { [bool]$defender.RealTimeProtectionEnabled } else { $null }
        pending_reboot = $pendingReboot
        system_critical_events_24h = $criticalEvents
        system_error_events_24h = $errorEvents
    }
}

function New-NeoAgenticAction {
    param(
        [string]$Action,
        [string]$Risk,
        [string]$Reason,
        [double]$Confidence = 0.7
    )
    [PSCustomObject]@{
        action = $Action
        risk = $Risk
        reason = $Reason
        confidence = [math]::Round($Confidence, 2)
        status = "planned"
    }
}

function Add-NeoUniqueAction {
    param(
        [System.Collections.Generic.List[object]]$Actions,
        [object]$Action
    )
    if (-not (@($Actions) | Where-Object { $_.action -eq $Action.action })) {
        $Actions.Add($Action) | Out-Null
    }
}

function New-NeoAgenticPlan {
    param(
        [string]$Goal,
        [object]$Snapshot,
        [int]$MaxActions = 3
    )

    $actions = [System.Collections.Generic.List[object]]::new()
    $goalText = $Goal.ToLowerInvariant()

    Add-NeoUniqueAction $actions (New-NeoAgenticAction -Action "AIPlan" -Risk "read_only" -Reason "Start with AI Doctor scoring and treatment ranking." -Confidence 0.95)

    if ($Snapshot.disk_c_free_pct -ne $null -and $Snapshot.disk_c_free_pct -lt 15) {
        Add-NeoUniqueAction $actions (New-NeoAgenticAction -Action "DeepScan" -Risk "read_only" -Reason "Drive C free space is below 15%; scan junk candidates first." -Confidence 0.9)
        Add-NeoUniqueAction $actions (New-NeoAgenticAction -Action "Cleaner" -Risk "low" -Reason "Safe temporary file cleanup may recover disk space." -Confidence 0.82)
    }
    if ($Snapshot.ram_used_pct -ne $null -and $Snapshot.ram_used_pct -gt 82) {
        Add-NeoUniqueAction $actions (New-NeoAgenticAction -Action "SystemDiagnostics" -Risk "read_only" -Reason "RAM pressure is high; inspect processes, services, and startup load." -Confidence 0.82)
    }
    if (($Snapshot.system_critical_events_24h + $Snapshot.system_error_events_24h) -gt 5 -or $goalText -match "error|fix|repair|trouble|crash|bsod") {
        Add-NeoUniqueAction $actions (New-NeoAgenticAction -Action "WindowsDoctor" -Risk "read_only" -Reason "Recent Windows errors or repair intent detected; correlate event logs before repair." -Confidence 0.86)
    }
    if ($goalText -match "clean|junk|space|storage") {
        Add-NeoUniqueAction $actions (New-NeoAgenticAction -Action "DeepScan" -Risk "read_only" -Reason "Goal asks for cleanup; scan before deleting." -Confidence 0.88)
        Add-NeoUniqueAction $actions (New-NeoAgenticAction -Action "Cleaner" -Risk "low" -Reason "Safe temp/cache cleanup after scan." -Confidence 0.8)
    }
    if ($goalText -match "slow|optimi[sz]e|performance|berat|lambat") {
        Add-NeoUniqueAction $actions (New-NeoAgenticAction -Action "SmartOptimize" -Risk "medium" -Reason "Goal asks for performance maintenance; run balanced optimization after diagnostics." -Confidence 0.76)
    }
    if ($goalText -match "network|dns|internet|wifi") {
        Add-NeoUniqueAction $actions (New-NeoAgenticAction -Action "Network" -Risk "high" -Reason "Network troubleshooting requested; reset flows require confirmation." -Confidence 0.72)
    }
    if ($goalText -match "security|virus|malware|threat|defender") {
        Add-NeoUniqueAction $actions (New-NeoAgenticAction -Action "Security" -Risk "high" -Reason "Security audit requested; keep Defender enabled and audit posture." -Confidence 0.78)
        Add-NeoUniqueAction $actions (New-NeoAgenticAction -Action "ThreatMonitor" -Risk "read_only" -Reason "Review suspicious persistence and threat signals." -Confidence 0.8)
    }
    if ($goalText -match "update|upgrade") {
        Add-NeoUniqueAction $actions (New-NeoAgenticAction -Action "Updates" -Risk "high" -Reason "Update repair may touch services/cache; confirmation required." -Confidence 0.7)
    }
    if ($goalText -match "dependency|skill|mcp|library|model|provider") {
        Add-NeoUniqueAction $actions (New-NeoAgenticAction -Action "AIEnvironment" -Risk "read_only" -Reason "Inventory model, skill, MCP, and runtime dependency readiness." -Confidence 0.92)
        Add-NeoUniqueAction $actions (New-NeoAgenticAction -Action "AIProviders" -Risk "read_only" -Reason "Check local/cloud model providers." -Confidence 0.88)
    }

    $selected = @($actions | Select-Object -First ([Math]::Max(1, $MaxActions)))
    [PSCustomObject]@{
        plan_id = "neo_agentic_" + (Get-Date -Format "yyyyMMdd_HHmmss")
        state = "PLAN"
        goal = $Goal
        snapshot = $Snapshot
        actions = $selected
        safety = [PSCustomObject]@{
            execution = "human_confirmed"
            autonomous_execution = $false
            remote_execution = "signed_manifest_only"
            secrets = "never_collect"
        }
    }
}

function ConvertTo-NeoJson {
    param([object]$Value)
    return ($Value | ConvertTo-Json -Depth 12)
}

function Write-NeoAgenticReport {
    param(
        [object]$Plan,
        [object]$AfterSnapshot = $null,
        [object[]]$Executed = @()
    )
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $jsonPath = Join-Path $Script:ReportsDir "NeoOptimize_Agentic_$stamp.json"
    $mdPath = Join-Path $Script:ReportsDir "NeoOptimize_Agentic_$stamp.md"
    $payload = [PSCustomObject]@{
        plan = $Plan
        executed = @($Executed)
        snapshot_after = $AfterSnapshot
        verification = if ($AfterSnapshot) {
            [PSCustomObject]@{
                ram_used_delta_pct = if ($Plan.snapshot.ram_used_pct -ne $null -and $AfterSnapshot.ram_used_pct -ne $null) { [math]::Round(($AfterSnapshot.ram_used_pct - $Plan.snapshot.ram_used_pct), 1) } else { $null }
                disk_free_delta_pct = if ($Plan.snapshot.disk_c_free_pct -ne $null -and $AfterSnapshot.disk_c_free_pct -ne $null) { [math]::Round(($AfterSnapshot.disk_c_free_pct - $Plan.snapshot.disk_c_free_pct), 1) } else { $null }
                critical_events_delta = if ($AfterSnapshot.system_critical_events_24h -ne $null) { $AfterSnapshot.system_critical_events_24h - $Plan.snapshot.system_critical_events_24h } else { $null }
            }
        } else { $null }
    }
    ConvertTo-NeoJson $payload | Set-Content -Path $jsonPath -Encoding UTF8

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# NEO Agentic Runtime") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("Identity: Saya adalah NEO (Neural Execution Operator), artificial intelligence yang dibangun di zenthralix-lab oleh nol_eight.") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("- Plan ID: `$($Plan.plan_id)`") | Out-Null
    $lines.Add("- Goal: $($Plan.goal)") | Out-Null
    $lines.Add("- Mode: observe -> diagnose -> plan -> approve -> act -> verify -> learn") | Out-Null
    $lines.Add("- Host: $($Plan.snapshot.computer_name) / $($Plan.snapshot.os) build $($Plan.snapshot.build)") | Out-Null
    $lines.Add("- RAM used: $($Plan.snapshot.ram_used_pct)%") | Out-Null
    $lines.Add("- Disk C free: $($Plan.snapshot.disk_c_free_pct)%") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("## Planned Actions") | Out-Null
    foreach ($a in @($Plan.actions)) {
        $lines.Add("- `$($a.action)` [$($a.risk), confidence $([int]($a.confidence * 100))%] - $($a.reason)") | Out-Null
    }
    if (@($Executed).Count -gt 0) {
        $lines.Add("") | Out-Null
        $lines.Add("## Executed Actions") | Out-Null
        foreach ($e in @($Executed)) {
            $lines.Add("- `$($e.action)` -> $($e.status), exit $($e.exit_code)") | Out-Null
        }
    }
    $lines.Add("") | Out-Null
    $lines.Add("JSON: `$jsonPath`") | Out-Null
    $lines | Set-Content -Path $mdPath -Encoding UTF8

    $memoryPath = Join-Path $Script:ReportsDir "memory.jsonl"
    Add-Content -Path $memoryPath -Value (ConvertTo-NeoJson $payload)
    [PSCustomObject]@{ json = $jsonPath; markdown = $mdPath; memory = $memoryPath }
}

function Test-NeoAgenticApproval {
    param([object]$Action)
    if ($AssumeYes -and $Action.risk -in @("read_only", "low")) { return $true }
    Write-Host ""
    Write-Host "NEO wants to run: $($Action.action)"
    Write-Host "Risk          : $($Action.risk)"
    Write-Host "Reason        : $($Action.reason)"
    $answer = Read-Host "Type YES to approve this action"
    return ($answer -eq "YES")
}

function Invoke-NeoAgenticAction {
    param([object]$Action)
    $result = [PSCustomObject]@{
        action = $Action.action
        risk = $Action.risk
        started_at = (Get-Date).ToUniversalTime().ToString("o")
        status = "skipped"
        exit_code = $null
    }
    if (-not (Test-Path $Script:EnginePath)) {
        $result.status = "engine_missing"
        return $result
    }
    if (-not (Test-NeoAgenticApproval -Action $Action)) {
        $result.status = "not_approved"
        return $result
    }
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$Script:EnginePath`"", "-Action", $Action.action, "-NoPause")
    if ($Action.risk -in @("read_only", "low")) { $args += "-AssumeYes" }
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList ($args -join " ") -WorkingDirectory $Script:Root -Wait -PassThru -WindowStyle Hidden
    $result.exit_code = $proc.ExitCode
    $result.status = if ($proc.ExitCode -eq 0) { "completed" } else { "failed" }
    $result.completed_at = (Get-Date).ToUniversalTime().ToString("o")
    return $result
}

function Invoke-NeoAgenticCycle {
    param([switch]$RunActions)
    $policy = Get-NeoAgenticPolicy
    $snapshot = Get-NeoAgenticSnapshot
    $max = if ($MaxActions -gt 0) { $MaxActions } else { [int]$policy.loop.max_actions_per_cycle }
    if ($max -le 0) { $max = 3 }
    $plan = New-NeoAgenticPlan -Goal $Goal -Snapshot $snapshot -MaxActions $max

    Write-Host ""
    Write-Host "NEO Agentic Runtime"
    Write-Host "==================="
    Write-Host "Saya adalah NEO (Neural Execution Operator), artificial intelligence yang dibangun di zenthralix-lab oleh nol_eight."
    Write-Host "Mode : observe -> diagnose -> plan -> approve -> act -> verify -> learn"
    Write-Host "Goal : $Goal"
    Write-Host ""
    foreach ($a in @($plan.actions)) {
        Write-Host ("- {0} [{1}] {2}" -f $a.action, $a.risk, $a.reason)
    }

    $executed = @()
    $shouldRun = $RunActions
    if (-not $shouldRun -and $Mode -eq "RunOnce") {
        $answer = Read-Host "Run approved planned actions now? Type YES"
        $shouldRun = ($answer -eq "YES")
    }
    if ($shouldRun) {
        foreach ($action in @($plan.actions)) {
            $executed += Invoke-NeoAgenticAction -Action $action
        }
    }
    $after = if ($shouldRun) { Get-NeoAgenticSnapshot } else { $null }
    $report = Write-NeoAgenticReport -Plan $plan -AfterSnapshot $after -Executed $executed
    Write-Host ""
    Write-Host "Report : $($report.markdown)"
    Write-Host "Memory : $($report.memory)"
    if (-not $NoOpen) { Start-Process notepad.exe -ArgumentList "`"$($report.markdown)`"" }
}

function Show-NeoAgenticStatus {
    Write-Host ""
    Write-Host "NEO Agentic Runtime Status"
    Write-Host "=========================="
    Write-Host "Policy : $Script:PolicyPath"
    Write-Host "Reports: $Script:ReportsDir"
    Write-Host "Mode   : human-confirmed, autonomous execution disabled"
    $latest = Get-ChildItem -Path $Script:ReportsDir -Filter "NeoOptimize_Agentic_*.md" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latest) { Write-Host "Latest : $($latest.FullName)" }
}

switch ($Mode) {
    "Status" { Show-NeoAgenticStatus }
    "Loop" {
        while ($true) {
            Invoke-NeoAgenticCycle -RunActions:$Execute
            Start-Sleep -Seconds ([Math]::Max(60, $IntervalSeconds))
        }
    }
    "RunOnce" { Invoke-NeoAgenticCycle -RunActions:$Execute }
    default { Invoke-NeoAgenticCycle -RunActions:$false }
}
