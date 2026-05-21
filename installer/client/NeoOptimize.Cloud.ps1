#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    NeoOptimize cloud connector status.
#>

param(
    [ValidateSet("Status", "Open")]
    [string]$Mode = "Status"
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:ConfigPath = Join-Path $Script:Root "config\NeoOptimize.Cloud.json"
$Script:ReportDir = Join-Path $Script:Root "reports\cloud"
if (-not (Test-Path $Script:ReportDir)) {
    New-Item -Path $Script:ReportDir -ItemType Directory -Force | Out-Null
}

function Read-CloudConfig {
    if (-not (Test-Path $Script:ConfigPath)) {
        throw "Cloud config not found: $Script:ConfigPath"
    }
    Get-Content -Path $Script:ConfigPath -Raw | ConvertFrom-Json
}

function Test-HttpEndpoint {
    param([string]$Url)
    if (-not $Url) { return "missing" }
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 8
        return "ok ($($response.StatusCode))"
    } catch {
        try {
            $response = Invoke-WebRequest -Uri $Url -Method Get -UseBasicParsing -TimeoutSec 8
            return "ok ($($response.StatusCode))"
        } catch {
            return "error: $($_.Exception.Message)"
        }
    }
}

function Mask-Value {
    param([string]$Value)
    if (-not $Value) { return "missing" }
    if ($Value.Length -le 12) { return "***" }
    return "$($Value.Substring(0, 8))...$($Value.Substring($Value.Length - 6))"
}

function Get-ConnectorStatus {
    $cfg = Read-CloudConfig
    $nullclaw = Get-Command $cfg.nullclaw.command -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        generated_at = (Get-Date).ToString("s")
        github = [PSCustomObject]@{
            repo_url = $cfg.github.repo_url
            status = Test-HttpEndpoint $cfg.github.repo_url
            token_env_present = [bool]$env:NEOOPTIMIZE_GITHUB_TOKEN
        }
        huggingface = [PSCustomObject]@{
            space_url = $cfg.huggingface.space_url
            status = Test-HttpEndpoint $cfg.huggingface.space_url
        }
        supabase = [PSCustomObject]@{
            url = if ($cfg.supabase.url) { $cfg.supabase.url } else { "missing" }
            publishable_key = Mask-Value $cfg.supabase.publishable_key
            status = if ($cfg.supabase.url) { Test-HttpEndpoint $cfg.supabase.url } else { "needs project URL" }
            service_key_env_present = [bool]$env:NEOOPTIMIZE_SUPABASE_SERVICE_KEY
        }
        e2b = [PSCustomObject]@{
            dashboard_url = $cfg.e2b.dashboard_url
            status = Test-HttpEndpoint $cfg.e2b.dashboard_url
            api_key_env_present = [bool]$env:E2B_API_KEY
        }
        nullclaw = [PSCustomObject]@{
            command = $cfg.nullclaw.command
            status = if ($nullclaw) { "ready ($($nullclaw.Source))" } else { "not found in PATH" }
        }
    }
}

function Write-StatusReport {
    $status = Get-ConnectorStatus
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $jsonPath = Join-Path $Script:ReportDir "NeoOptimize_Cloud_Status_$stamp.json"
    $mdPath = Join-Path $Script:ReportDir "NeoOptimize_Cloud_Status_$stamp.md"
    $status | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

    $md = @"
# NeoOptimize Cloud Connector Status

Generated: $($status.generated_at)

| Connector | Status | Notes |
| --- | --- | --- |
| GitHub | $($status.github.status) | token env present: $($status.github.token_env_present) |
| Hugging Face Space | $($status.huggingface.status) | $($status.huggingface.space_url) |
| Supabase | $($status.supabase.status) | url: $($status.supabase.url), publishable key: $($status.supabase.publishable_key) |
| E2B | $($status.e2b.status) | api key env present: $($status.e2b.api_key_env_present) |
| NullClaw | $($status.nullclaw.status) | command: $($status.nullclaw.command) |

Private tokens should stay in environment variables, not in distributable config.
"@
    Set-Content -Path $mdPath -Value $md -Encoding UTF8

    Write-Host ""
    Write-Host "NeoOptimize Cloud Connector Status"
    Write-Host "=================================="
    Write-Host "GitHub      : $($status.github.status)"
    Write-Host "HF Space    : $($status.huggingface.status)"
    Write-Host "Supabase    : $($status.supabase.status)"
    Write-Host "E2B         : $($status.e2b.status)"
    Write-Host "NullClaw    : $($status.nullclaw.status)"
    Write-Host ""
    Write-Host "Report      : $mdPath"
    Write-Host ""
    Start-Process notepad.exe -ArgumentList "`"$mdPath`""
}

function Open-ConnectorPages {
    $cfg = Read-CloudConfig
    foreach ($url in @($cfg.github.repo_url, $cfg.huggingface.space_url, $cfg.e2b.dashboard_url)) {
        if ($url) { Start-Process $url }
    }
}

if ($Mode -eq "Open") {
    Open-ConnectorPages
} else {
    Write-StatusReport
}
