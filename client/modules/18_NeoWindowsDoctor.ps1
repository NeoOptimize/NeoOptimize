#Requires -Version 5.1
<#
.SYNOPSIS
    NEO Windows Doctor: anomaly detection and conservative repair workflow.
.DESCRIPTION
    Scan mode is read-only and correlates SystemDiagnostics, NeoCore AI plan,
    MCP connector context, and NullClaw bridge diagnostics. Fix mode requires
    explicit high-risk consent and runs the conservative Windows repair lane.
#>

param(
    [ValidateSet("Scan", "Fix")]
    [string]$Mode = "Scan",
    [int]$EventDays = 7,
    [string]$ArgsJson = ""
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

try { . "$PSScriptRoot\..\lib\Common.ps1" } catch { Write-Verbose $_.Exception.Message }
try { . "$PSScriptRoot\..\lib\NeoCapabilityCatalog.ps1" } catch { Write-Verbose $_.Exception.Message }

if ($ArgsJson) {
    try {
        $parsedArgs = $ArgsJson | ConvertFrom-Json
        if ($parsedArgs.Mode) { $Mode = [string]$parsedArgs.Mode }
        if ($parsedArgs.EventDays) { $EventDays = [int]$parsedArgs.EventDays }
    } catch { Write-Verbose $_.Exception.Message }
}

function Out-Info { param([string]$Message) if (Get-Command Write-Info -ErrorAction SilentlyContinue) { Write-Info $Message } else { Write-Host "[*] $Message" } }
function Out-OK { param([string]$Message) if (Get-Command Write-OK -ErrorAction SilentlyContinue) { Write-OK $Message } else { Write-Host "[+] $Message" } }
function Out-Warn { param([string]$Message) if (Get-Command Write-Warn -ErrorAction SilentlyContinue) { Write-Warn $Message } else { Write-Host "[!] $Message" } }
function Out-Err { param([string]$Message) if (Get-Command Write-Err -ErrorAction SilentlyContinue) { Write-Err $Message } else { Write-Host "[X] $Message" } }
function Out-Step { param([string]$Message) if (Get-Command Write-Step -ErrorAction SilentlyContinue) { Write-Step $Message } else { Write-Host "`n== $Message ==" } }

function Invoke-NeoDoctorCapture {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @()
    )

    if (-not (Test-Path $FilePath)) {
        return [PSCustomObject]@{ ok = $false; output = ""; error = "Missing file: $FilePath" }
    }
    try {
        $output = & $FilePath @Arguments 2>&1
        return [PSCustomObject]@{ ok = $true; output = (@($output) -join "`r`n"); error = "" }
    } catch {
        return [PSCustomObject]@{ ok = $false; output = ""; error = $_.Exception.Message }
    }
}

function ConvertFrom-LastJsonObject {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $lines = @($Text -split "\r?\n")
    foreach ($line in @($lines | Select-Object -Last 30)) {
        $trimmed = $line.Trim()
        if (-not $trimmed.StartsWith("{")) { continue }
        try { return ($trimmed | ConvertFrom-Json) } catch { Write-Verbose $_.Exception.Message }
    }
    return $null
}

function Get-NeoFindingStats {
    param($Diagnostics)

    $findings = @()
    if ($Diagnostics -and $Diagnostics.findings) { $findings = @($Diagnostics.findings) }
    $critical = @($findings | Where-Object { $_.severity -eq "Critical" }).Count
    $high = @($findings | Where-Object { $_.severity -eq "High" }).Count
    $medium = @($findings | Where-Object { $_.severity -eq "Medium" }).Count
    $low = @($findings | Where-Object { $_.severity -eq "Low" }).Count
    $anomalyScore = [math]::Min(100, ($critical * 35) + ($high * 20) + ($medium * 8) + ($low * 3))

    return [PSCustomObject]@{
        total = $findings.Count
        critical = $critical
        high = $high
        medium = $medium
        low = $low
        anomaly_score = [int]$anomalyScore
        repair_recommended = ($critical -gt 0 -or $high -gt 0)
    }
}

function New-NeoDoctorMarkdown {
    param($Report)

    $findingLines = @($Report.diagnostics.findings | Select-Object -First 12 | ForEach-Object {
        "- [$($_.severity)] $($_.title) - $($_.recommendation)"
    }) -join "`r`n"
    if ([string]::IsNullOrWhiteSpace($findingLines)) { $findingLines = "- No major findings." }

@"
# NEO Windows Doctor Report

Generated: $($Report.generated_at)
Mode: $($Report.mode)
Endpoint: $($Report.endpoint.computer_name)

## Health

- Diagnostics score: $($Report.diagnostics.score)
- Grade: $($Report.diagnostics.grade)
- Anomaly score: $($Report.anomaly.anomaly_score)
- Findings: $($Report.anomaly.total) total, $($Report.anomaly.critical) critical, $($Report.anomaly.high) high
- Repair recommended: $($Report.anomaly.repair_recommended)

## Top Findings

$findingLines

## AI Plan

$($Report.ai_plan_text)

## Capability Treatment Plan

$($Report.capability_plan_text)

## MCP Context

MCP bridge ready: $($Report.mcp_context.public_safe)
Skills bundled: $($Report.mcp_context.bundle.skills)
MCP files bundled: $($Report.mcp_context.bundle.mcp_connectors)

## NullClaw Bridge

$($Report.nullclaw_summary)
"@
}

$rootDir = Split-Path -Parent $PSScriptRoot
$reportDir = Join-Path $rootDir "reports\doctor"
if (-not (Test-Path $reportDir)) { New-Item -Path $reportDir -ItemType Directory -Force | Out-Null }
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jsonReportPath = Join-Path $reportDir "NeoWindowsDoctor_$stamp.json"
$mdReportPath = Join-Path $reportDir "NeoWindowsDoctor_$stamp.md"

if (Get-Command Write-ModuleHeader -ErrorAction SilentlyContinue) {
    Write-ModuleHeader "18" "NEO" "WINDOWS DOCTOR"
} else {
    Write-Host "`nNEO Windows Doctor`n"
}

if ($Mode -eq "Fix") {
    $allowed = $true
    if (Get-Command Test-NeoHighRiskConsent -ErrorAction SilentlyContinue) {
        $allowed = Test-NeoHighRiskConsent -ActionName "Windows Error Fix" -RiskLevel "High" -Reason "Runs WinRE enable, DISM RestoreHealth, SFC, update reset, service recovery, and writes repair logs."
    }
    if (-not $allowed) {
        Out-Warn "Windows Error Fix cancelled. Scan mode remains available."
        if (Get-Command Wait-AnyKey -ErrorAction SilentlyContinue) { Wait-AnyKey }
        exit 0
    }

    if (Get-Command New-RestorePoint -ErrorAction SilentlyContinue) {
        New-RestorePoint "NeoOptimize Windows Error Fix $stamp" | Out-Null
    }
}

Out-Step "Running Windows diagnostics"
$diagnosticsMode = if ($Mode -eq "Fix") { "Repair" } else { "Report" }
$diagnosticsPath = Join-Path $PSScriptRoot "16_SystemDiagnostics.ps1"
$diagnosticsRun = Invoke-NeoDoctorCapture -FilePath $diagnosticsPath -Arguments @("-Mode", $diagnosticsMode, "-EventDays", "$EventDays")
$diagnostics = ConvertFrom-LastJsonObject $diagnosticsRun.output
if (-not $diagnostics) {
    $diagnostics = [PSCustomObject]@{
        score = 0
        grade = "Unknown"
        findings = @([PSCustomObject]@{
            id = "NEO-DOCTOR-DIAG"
            category = "Runtime"
            severity = "High"
            title = "SystemDiagnostics did not return JSON"
            detail = $diagnosticsRun.error
            recommendation = "Run SystemDiagnostics directly and review terminal output."
        })
        actions = @()
    }
}

Out-Step "Collecting NEO AI plan"
$aiAgentPath = Join-Path $rootDir "NeoOptimize.AIAgent.ps1"
$aiRun = Invoke-NeoDoctorCapture -FilePath $aiAgentPath -Arguments @("-Mode", "Plan", "-NoOpen")
$aiPlanText = if ($aiRun.output) { $aiRun.output.Trim() } else { "AI plan unavailable: $($aiRun.error)" }

Out-Step "Mapping safe capability treatment plan"
$capabilityPlanText = "Capability catalog unavailable."
$capabilityPlan = $null
if (Get-Command New-NeoCapabilityPlan -ErrorAction SilentlyContinue) {
    try {
        $capabilityPlan = New-NeoCapabilityPlan `
            -Commands @("SYSTEM_DIAGNOSTICS", "SYSTEM_REPAIR", "SECURITY_SCAN", "CLEAN", "OPTIMIZE", "NETWORK_TEST", "UPDATES") `
            -Actions @("WindowsDoctor", "SystemDiagnostics", "SystemRepair", "Security", "Cleaner", "SmartOptimize", "Network", "Updates") `
            -Limit 12
        $capabilityPlanText = Format-NeoCapabilityCatalogSummary -Capabilities @($capabilityPlan.capabilities) -Limit 12
    } catch {
        $capabilityPlanText = "Capability catalog failed: $($_.Exception.Message)"
    }
}

Out-Step "Collecting MCP connector context"
$mcpPath = Join-Path $rootDir "tools\neo_mcp_bridge.ps1"
$mcpRun = Invoke-NeoDoctorCapture -FilePath $mcpPath -Arguments @("-Mode", "context")
$mcpContext = ConvertFrom-LastJsonObject $mcpRun.output
if (-not $mcpContext) {
    $mcpContext = [PSCustomObject]@{
        public_safe = $false
        bundle = [PSCustomObject]@{ skills = 0; mcp_connectors = 0 }
        error = $mcpRun.error
    }
}

Out-Step "Collecting NullClaw bridge doctor context"
$nullClawPath = Join-Path $rootDir "tools\nullclaw.ps1"
$nullClawRun = Invoke-NeoDoctorCapture -FilePath $nullClawPath -Arguments @("doctor")
$nullClawSummary = if ($nullClawRun.output) { $nullClawRun.output.Trim() } else { "NullClaw bridge unavailable: $($nullClawRun.error)" }

$endpoint = [PSCustomObject]@{
    computer_name = $env:COMPUTERNAME
    user = $env:USERNAME
    os = ""
    build = ""
}
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $endpoint.os = [string]$os.Caption
        $endpoint.build = [string]$os.BuildNumber
    }
} catch { Write-Verbose $_.Exception.Message }

$anomaly = Get-NeoFindingStats -Diagnostics $diagnostics

$report = [PSCustomObject]@{
    schema_version = "1.0"
    generated_at = (Get-Date).ToString("o")
    mode = $Mode
    endpoint = $endpoint
    diagnostics = $diagnostics
    anomaly = $anomaly
    ai_plan_text = $aiPlanText
    capability_plan = $capabilityPlan
    capability_plan_text = $capabilityPlanText
    mcp_context = $mcpContext
    nullclaw_summary = $nullClawSummary
    report_path = $jsonReportPath
    markdown_report_path = $mdReportPath
}

$report | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonReportPath -Encoding UTF8
New-NeoDoctorMarkdown -Report $report | Set-Content -Path $mdReportPath -Encoding UTF8

Out-Step "NEO Windows Doctor summary"
if ($anomaly.repair_recommended) {
    Out-Warn "Anomaly score $($anomaly.anomaly_score)/100. Repair is recommended after review."
    Out-Info "Use WindowsErrorFix only when you are ready to run conservative repair."
} else {
    Out-OK "Anomaly score $($anomaly.anomaly_score)/100. No urgent repair lane required."
}
Out-Info "Diagnostics score: $($diagnostics.score)/100 ($($diagnostics.grade))"
Out-Info "Report: $jsonReportPath"
Out-Info "Show me: $mdReportPath"

$report | ConvertTo-Json -Depth 10 -Compress | Write-Output
if (Get-Command Wait-AnyKey -ErrorAction SilentlyContinue) { Wait-AnyKey }
