#Requires -Version 5.1
<#
.SYNOPSIS
    Train the local NeoCore policy model from bundled and collected endpoint examples.

.DESCRIPTION
    This trainer is intentionally lightweight and offline. It updates the
    NeoCore module ranking weights from JSONL examples and previous
    NeoOptimize AI report JSON files without sending data to any server.
#>

param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
    [string]$DatasetPath,
    [string]$PolicyPath,
    [switch]$NoBackup
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

if (-not $DatasetPath) { $DatasetPath = Join-Path $Root "datasets\neocore_training_seed.jsonl" }
if (-not $PolicyPath) { $PolicyPath = Join-Path $Root "models\NeoCore.Policy.json" }

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -Path $Path -Raw | ConvertFrom-Json
}

function Convert-SnapshotToFeatures {
    param($Snapshot)

    function Clamp01([double]$Value) {
        return [math]::Max(0, [math]::Min(1, $Value))
    }

    $diskFreePct = 100.0
    $ramUsedPct = 0.0
    $startup = 0.0
    $process = 0.0
    $uptime = 0.0
    $signatureAge = 0.0
    try { $diskFreePct = [double]$Snapshot.disk_c_free_pct } catch {}
    try { $ramUsedPct = [double]$Snapshot.ram_used_pct } catch {}
    try { $startup = [double]$Snapshot.startup_count } catch {}
    try { $process = [double]$Snapshot.process_count } catch {}
    try { $uptime = [double]$Snapshot.uptime_days } catch {}
    try { $signatureAge = [double]$Snapshot.defender_signature_age_days } catch {}

    $diskPressure = Clamp01 ((25 - $diskFreePct) / 25)
    $memoryPressure = Clamp01 (($ramUsedPct - 55) / 45)
    $startupLoad = Clamp01 ($startup / 45)
    $processLoad = Clamp01 (($process - 120) / 220)
    $uptimePressure = Clamp01 ($uptime / 21)
    $firewall = if (@($Snapshot.firewall_disabled_profiles).Count -gt 0) { 1.0 } else { 0.0 }
    $defender = if ($Snapshot.defender_realtime -eq $false) { 1.0 } else { 0.0 }
    $signatureRisk = Clamp01 ($signatureAge / 21)
    $updateServiceRisk = if ($Snapshot.windows_update_service_status -and $Snapshot.windows_update_service_status -ne "Running") { 0.65 } else { 0.0 }
    $pendingRebootRisk = if ($Snapshot.pending_reboot) { 0.75 } else { 0.0 }
    $updateRisk = [math]::Max($signatureRisk, [math]::Max($updateServiceRisk, $pendingRebootRisk))
    $criticalStopped = @($Snapshot.critical_services_stopped).Count
    $autoStopped = 0.0
    try { $autoStopped = [double]$Snapshot.auto_services_stopped } catch {}
    $serviceRisk = Clamp01 (($autoStopped / 18) + ([double]$criticalStopped / 6))
    $networkIssues = 0.0
    try { $networkIssues = [double]$Snapshot.network_issue_count } catch {}
    $networkRisk = Clamp01 (($networkIssues / 3) + ($uptimePressure * 0.12))
    $powerPlan = [string]$Snapshot.active_power_plan
    $powerRisk = 0.0
    if ($powerPlan -match "power saver|balanced|penghemat") { $powerRisk = [math]::Max($powerRisk, 0.45) }
    if ($Snapshot.on_battery) { $powerRisk = [math]::Max($powerRisk, 0.35) }
    $powerRisk = [math]::Max($powerRisk, (Clamp01 (($memoryPressure * 0.25) + ($processLoad * 0.2))))
    $privacySignals = 0.0
    try { $privacySignals = [double]$Snapshot.privacy_signal_count } catch {}
    $privacyRisk = Clamp01 (($privacySignals / 5) + ($startupLoad * 0.15) + ($processLoad * 0.10))
    $repairRisk = [math]::Max($pendingRebootRisk * 0.7, [math]::Max($updateRisk * 0.55, [math]::Max($serviceRisk * 0.45, $diskPressure * 0.3)))
    $inventoryGap = if (-not $Snapshot.rmm_agent_installed) {
        1.0
    } elseif ($Snapshot.rmm_agent_status -ne "Running") {
        0.65
    } else {
        0.15
    }
    $priorReports = 0
    try { $priorReports = [int]$Snapshot.prior_ai_reports } catch {}
    $baselineNeed = if ($priorReports -le 0) { 0.70 } else { 0.25 }

    return [ordered]@{
        disk_pressure = [math]::Round($diskPressure, 4)
        memory_pressure = [math]::Round($memoryPressure, 4)
        startup_load = [math]::Round($startupLoad, 4)
        process_load = [math]::Round($processLoad, 4)
        uptime_pressure = [math]::Round($uptimePressure, 4)
        firewall_risk = $firewall
        defender_risk = $defender
        update_risk = [math]::Round($updateRisk, 4)
        service_risk = [math]::Round($serviceRisk, 4)
        network_risk = [math]::Round($networkRisk, 4)
        power_risk = [math]::Round($powerRisk, 4)
        privacy_risk = [math]::Round($privacyRisk, 4)
        repair_risk = [math]::Round($repairRisk, 4)
        inventory_gap = [math]::Round($inventoryGap, 4)
        baseline_need = [math]::Round($baselineNeed, 4)
    }
}

function Add-TrainingExample {
    param(
        [System.Collections.Generic.List[object]]$Examples,
        [object]$Features,
        [string[]]$Modules,
        [int]$HealthScore = 80
    )
    if (-not $Features -or -not $Modules -or $Modules.Count -eq 0) { return }
    $Examples.Add([PSCustomObject]@{
        features = [PSCustomObject]$Features
        modules = @($Modules | Select-Object -Unique)
        health_score = $HealthScore
    }) | Out-Null
}

if (-not (Test-Path $PolicyPath)) { throw "Policy not found: $PolicyPath" }
$policy = Read-JsonFile $PolicyPath
$examples = [System.Collections.Generic.List[object]]::new()

if (Test-Path $DatasetPath) {
    Get-Content -Path $DatasetPath | Where-Object { $_.Trim() } | ForEach-Object {
        $item = $_ | ConvertFrom-Json
        Add-TrainingExample -Examples $examples -Features $item.features -Modules @($item.modules) -HealthScore ([int]$item.health_score)
    }
}

$aiDir = Join-Path $Root "reports\ai"
if (Test-Path $aiDir) {
    Get-ChildItem -Path $aiDir -Filter "NeoOptimize_AI_Agent_*.json" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 200 |
        ForEach-Object {
            try {
                $report = Read-JsonFile $_.FullName
                if ($report.snapshot) {
                    $features = Convert-SnapshotToFeatures $report.snapshot
                    Add-TrainingExample -Examples $examples -Features $features -Modules @("AgentAudit") -HealthScore 80
                }
            } catch {}
        }
}

if ($examples.Count -eq 0) { throw "No training examples found." }

$featureNames = @($policy.weights.PSObject.Properties.Name)
$moduleNames = @($policy.modules.PSObject.Properties.Name)

foreach ($module in $moduleNames) {
    foreach ($featureName in $featureNames) {
        $positive = 0.0
        $positiveCount = 0
        $negative = 0.0
        $negativeCount = 0

        foreach ($example in $examples) {
            $value = [double]$example.features.$featureName
            if (@($example.modules) -contains $module) {
                $positive += $value
                $positiveCount++
            } else {
                $negative += $value
                $negativeCount++
            }
        }

        $posAvg = if ($positiveCount -gt 0) { $positive / $positiveCount } else { 0.0 }
        $negAvg = if ($negativeCount -gt 0) { $negative / $negativeCount } else { 0.0 }
        $learned = [math]::Max(0, $posAvg - ($negAvg * 0.45))
        $old = 0.0
        try { $old = [double]$policy.modules.$module.features.$featureName } catch {}
        $newValue = [math]::Round(($old * 0.65) + ($learned * 1.35), 4)
        if ($policy.modules.$module.features.PSObject.Properties.Name -contains $featureName) {
            $policy.modules.$module.features.$featureName = $newValue
        } else {
            $policy.modules.$module.features | Add-Member -NotePropertyName $featureName -NotePropertyValue $newValue
        }
    }
}

foreach ($featureName in $featureNames) {
    $sum = 0.0
    foreach ($example in $examples) {
        $sum += [double]$example.features.$featureName
    }
    $avg = $sum / $examples.Count
    $oldWeight = 0.0
    try { $oldWeight = [double]$policy.weights.$featureName } catch {}
    $newWeight = [math]::Round([math]::Max(3, ($oldWeight * 0.80) + ($avg * 18)), 2)
    if ($policy.weights.PSObject.Properties.Name -contains $featureName) {
        $policy.weights.$featureName = $newWeight
    } else {
        $policy.weights | Add-Member -NotePropertyName $featureName -NotePropertyValue $newWeight
    }
}

$policy.model.trained_at = (Get-Date).ToString("s")
$policy.model.training_examples = $examples.Count

if (-not $NoBackup) {
    $backupDir = Join-Path $Root "backup\models"
    if (-not (Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory -Force | Out-Null }
    Copy-Item -Path $PolicyPath -Destination (Join-Path $backupDir ("NeoCore.Policy_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))) -Force
}

$policy | ConvertTo-Json -Depth 12 | Set-Content -Path $PolicyPath -Encoding UTF8
Write-Host "NeoCore training complete."
Write-Host "Examples : $($examples.Count)"
Write-Host "Policy   : $PolicyPath"
