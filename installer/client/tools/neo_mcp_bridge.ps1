#Requires -Version 5.1
<#
.SYNOPSIS
    Safe local MCP/connector inventory bridge for NEO.
.DESCRIPTION
    Reports connector and bundle readiness without printing secrets. This is
    intentionally read-only for public builds.
#>

param(
    [ValidateSet("status", "context")]
    [string]$Mode = "status"
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Test-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    try {
        Get-Content -Path $Path -Raw | ConvertFrom-Json | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Get-EnvPresence {
    param([string[]]$Names)
    foreach ($name in $Names) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $true }
    }
    return $false
}

function Get-CatalogCount {
    param([string]$RelativePath)
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path $path)) { return 0 }
    return @(Get-ChildItem -Path $path -Filter "*.json" -File -ErrorAction SilentlyContinue).Count
}

$rmmConfig = Join-Path $root "config\NeoOptimize.RMM.json"
$modelConfig = Join-Path $root "config\NeoOptimize.ModelAgent.json"
$aiEnvironment = Join-Path $root "config\NeoOptimize.AIEnvironment.json"
$bundleConfig = Join-Path $root "config\NeoOptimize.Bundle.json"

$status = [ordered]@{
    schema_version = "1.0"
    generated_at = (Get-Date).ToString("o")
    mode = $Mode
    root = $root
    public_safe = $true
    secret_values_redacted = $true
    bundle = [ordered]@{
        config_valid = Test-JsonFile $bundleConfig
        skills = Get-CatalogCount "skills"
        mcp_connectors = Get-CatalogCount "mcp"
        tools_present = [ordered]@{
            self_test = (Test-Path (Join-Path $root "tools\Invoke-NeoOptimizeSelfTest.ps1"))
            nullclaw_bridge = (Test-Path (Join-Path $root "tools\nullclaw.ps1"))
            mcp_bridge = (Test-Path (Join-Path $root "tools\neo_mcp_bridge.ps1"))
        }
    }
    connectors = @(
        [ordered]@{
            id = "rmm"
            name = "RMM Control Plane"
            configured = (Test-JsonFile $rmmConfig)
            access = "server"
            secret_policy = "server_only"
        },
        [ordered]@{
            id = "local_model"
            name = "Ollama / Local Model"
            configured = (Test-JsonFile $modelConfig)
            access = "local"
            secret_policy = "no_secret_required"
        },
        [ordered]@{
            id = "huggingface_spaces"
            name = "Hugging Face Spaces"
            configured = (Get-EnvPresence @("NEOOPTIMIZE_HF_TOKEN", "HF_TOKEN", "HUGGINGFACEHUB_API_TOKEN"))
            access = "cloud"
            secret_policy = "environment_variable"
        },
        [ordered]@{
            id = "e2b"
            name = "E2B Sandbox"
            configured = (Get-EnvPresence @("E2B_API_KEY", "NEOOPTIMIZE_E2B_API_KEY"))
            access = "server"
            secret_policy = "environment_variable"
        },
        [ordered]@{
            id = "supabase"
            name = "Supabase Mirror"
            configured = (Get-EnvPresence @("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"))
            access = "server"
            secret_policy = "service_role_never_frontend"
        },
        [ordered]@{
            id = "openfang"
            name = "OpenFang Operator Context"
            configured = (Get-EnvPresence @("OPENFANG_API_KEY", "NEOOPTIMIZE_OPENFANG_KEY"))
            access = "server"
            secret_policy = "server_only"
        },
        [ordered]@{
            id = "nullclaw"
            name = "NullClaw Local Operator"
            configured = (Test-Path (Join-Path $root "tools\nullclaw.ps1"))
            access = "local"
            secret_policy = "local_cli"
        }
    )
}

if ($Mode -eq "context") {
    $status["ai_environment_valid"] = Test-JsonFile $aiEnvironment
    $status["skill_files"] = @()
    $skillsDir = Join-Path $root "skills"
    if (Test-Path $skillsDir) {
        $status["skill_files"] = @(Get-ChildItem -Path $skillsDir -Filter "*.json" -File | Select-Object -ExpandProperty Name)
    }
    $status["mcp_files"] = @()
    $mcpDir = Join-Path $root "mcp"
    if (Test-Path $mcpDir) {
        $status["mcp_files"] = @(Get-ChildItem -Path $mcpDir -Filter "*.json" -File | Select-Object -ExpandProperty Name)
    }
}

[PSCustomObject]$status | ConvertTo-Json -Depth 8
