#Requires -Version 5.1
<#
.SYNOPSIS
    NeoOptimize safety-first capability catalog helper.

.DESCRIPTION
    Reads the structured capability catalog used by NEO AI, endpoint sync,
    and OpenFang operator workflows. The catalog is intentionally metadata
    rich: every capability carries risk, preflight, verification, telemetry,
    rollback, and reference data.
#>

Set-StrictMode -Off

function Get-NeoCapabilityCatalogPath {
    $override = [Environment]::GetEnvironmentVariable("NEOOPTIMIZE_CAPABILITY_CATALOG")
    if (-not [string]::IsNullOrWhiteSpace($override)) { return $override }

    $clientRoot = Split-Path -Parent $PSScriptRoot
    return (Join-Path $clientRoot "config\NeoOptimize.CommandCatalog.json")
}

function Read-NeoCapabilityCatalog {
    param([switch]$NoCache)

    $path = Get-NeoCapabilityCatalogPath
    if (-not (Test-Path $path)) {
        return [PSCustomObject]@{
            schema_version = "0"
            name = "NeoOptimize Capability Catalog"
            capabilities = @()
            references = @()
            default_policy = [PSCustomObject]@{}
        }
    }

    if (-not $NoCache -and $Script:NeoCapabilityCatalogCache -and $Script:NeoCapabilityCatalogCachePath -eq $path) {
        return $Script:NeoCapabilityCatalogCache
    }

    try {
        $catalog = Get-Content -Path $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $catalog.capabilities) {
            $catalog | Add-Member -NotePropertyName "capabilities" -NotePropertyValue @() -Force
        }
        $Script:NeoCapabilityCatalogCache = $catalog
        $Script:NeoCapabilityCatalogCachePath = $path
        return $catalog
    } catch {
        Write-Warning "Neo capability catalog invalid: $($_.Exception.Message)"
        return [PSCustomObject]@{
            schema_version = "invalid"
            name = "NeoOptimize Capability Catalog"
            capabilities = @()
            references = @()
            default_policy = [PSCustomObject]@{}
            error = $_.Exception.Message
        }
    }
}

function Get-NeoCapabilityItems {
    $catalog = Read-NeoCapabilityCatalog
    return @($catalog.capabilities)
}

function Get-NeoCapability {
    param([string]$Id)

    if ([string]::IsNullOrWhiteSpace($Id)) { return $null }
    $needle = $Id.Trim()
    return @(Get-NeoCapabilityItems | Where-Object { [string]$_.id -ieq $needle } | Select-Object -First 1)[0]
}

function Get-NeoCapabilityByRmmCommand {
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) { return @() }
    $needle = $Command.Trim().ToUpperInvariant()
    return @(Get-NeoCapabilityItems | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.rmm_command) -and ([string]$_.rmm_command).ToUpperInvariant() -eq $needle
    })
}

function Get-NeoCapabilityByLocalAction {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action)) { return @() }
    $needle = $Action.Trim()
    return @(Get-NeoCapabilityItems | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.local_action) -and [string]$_.local_action -ieq $needle
    })
}

function Search-NeoCapabilities {
    param(
        [string]$Query = "",
        [string]$Category = "",
        [string]$RiskLevel = "",
        [int]$Limit = 20
    )

    $items = Get-NeoCapabilityItems
    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        $items = @($items | Where-Object { [string]$_.category -ieq $Category })
    }
    if (-not [string]::IsNullOrWhiteSpace($RiskLevel)) {
        $items = @($items | Where-Object { [string]$_.risk_level -ieq $RiskLevel })
    }
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        $terms = @($Query -split '\s+' | Where-Object { $_ })
        foreach ($term in $terms) {
            $escaped = [regex]::Escape($term)
            $items = @($items | Where-Object {
                ([string]$_.id -match $escaped) -or
                ([string]$_.title -match $escaped) -or
                ([string]$_.category -match $escaped) -or
                ([string]$_.intent -match $escaped) -or
                ([string]$_.local_action -match $escaped) -or
                ([string]$_.rmm_command -match $escaped)
            })
        }
    }

    if ($Limit -gt 0) { return @($items | Select-Object -First $Limit) }
    return @($items)
}

function Get-NeoCapabilityRiskRank {
    param([string]$RiskLevel)

    switch -Regex ([string]$RiskLevel) {
        '^read_only$' { return 0 }
        '^low$' { return 1 }
        '^medium$' { return 2 }
        '^high$' { return 3 }
        '^critical$' { return 4 }
        default { return 2 }
    }
}

function Test-NeoCapabilityAllowed {
    param(
        [object]$Capability,
        [switch]$Remote,
        [switch]$Confirmed,
        [switch]$SignedManifest
    )

    if (-not $Capability) {
        return [PSCustomObject]@{ allowed = $false; reason = "Capability not found" }
    }

    $risk = [string]$Capability.risk_level
    $rank = Get-NeoCapabilityRiskRank $risk
    if ($Remote -and -not $SignedManifest) {
        return [PSCustomObject]@{ allowed = $false; reason = "Remote capability requires signed manifest" }
    }
    if ($rank -ge 2 -and -not $Confirmed) {
        return [PSCustomObject]@{ allowed = $false; reason = "Capability '$($Capability.id)' requires operator confirmation" }
    }
    return [PSCustomObject]@{ allowed = $true; reason = "allowed" }
}

function New-NeoCapabilityPlan {
    param(
        [string[]]$Commands = @(),
        [string[]]$Actions = @(),
        [string]$Query = "",
        [int]$Limit = 10
    )

    $map = [ordered]@{}
    foreach ($cmd in @($Commands)) {
        foreach ($cap in @(Get-NeoCapabilityByRmmCommand -Command $cmd)) {
            if ($cap -and -not $map.Contains([string]$cap.id)) { $map[[string]$cap.id] = $cap }
        }
    }
    foreach ($action in @($Actions)) {
        foreach ($cap in @(Get-NeoCapabilityByLocalAction -Action $action)) {
            if ($cap -and -not $map.Contains([string]$cap.id)) { $map[[string]$cap.id] = $cap }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        foreach ($cap in @(Search-NeoCapabilities -Query $Query -Limit $Limit)) {
            if ($cap -and -not $map.Contains([string]$cap.id)) { $map[[string]$cap.id] = $cap }
        }
    }

    $items = @($map.Values)
    if ($Limit -gt 0) { $items = @($items | Select-Object -First $Limit) }

    return [PSCustomObject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        count = @($items).Count
        capabilities = @($items)
    }
}

function Format-NeoCapabilityLine {
    param([object]$Capability)

    if (-not $Capability) { return "" }
    $cmd = if ($Capability.rmm_command) { [string]$Capability.rmm_command } else { "local-only" }
    $dryRun = if ($Capability.supports_dry_run) { "dry-run" } else { "apply" }
    return "- $($Capability.title) [$($Capability.risk_level), $dryRun] -> action $($Capability.local_action), RMM $cmd`r`n  Intent: $($Capability.intent)"
}

function Format-NeoCapabilityCatalogSummary {
    param(
        [object[]]$Capabilities = @(),
        [int]$Limit = 12
    )

    if (-not $Capabilities -or @($Capabilities).Count -eq 0) {
        $Capabilities = Get-NeoCapabilityItems
    }
    $items = @($Capabilities | Select-Object -First $Limit)
    if ($items.Count -eq 0) { return "No capabilities registered." }
    return (@($items | ForEach-Object { Format-NeoCapabilityLine -Capability $_ }) -join "`r`n")
}

function Get-NeoOperatorTerminalDenyPatterns {
    $cap = Get-NeoCapability "openfang.authorized_terminal"
    if ($cap -and $cap.deny_patterns) { return @($cap.deny_patterns | ForEach-Object { [string]$_ }) }
    return @()
}
