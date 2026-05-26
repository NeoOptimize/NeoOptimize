#Requires -Version 5.1
<#
.SYNOPSIS
    NeoOptimize NullClaw local bridge bootstrap.

.DESCRIPTION
    Public NeoOptimize bundles a read-only NullClaw compatibility bridge. This
    helper verifies the bridge and reports whether an external NullClaw CLI is
    also present.
#>

[CmdletBinding()]
param(
    [switch]$Status,
    [switch]$Onboard
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Bridge = Join-Path $Root "tools\nullclaw.ps1"

Write-Host "[NeoOptimize NullClaw] Bridge path: $Bridge"
if (-not (Test-Path $Bridge)) {
    throw "NullClaw bridge is missing from the NeoOptimize bundle."
}

$external = Get-Command nullclaw.exe -ErrorAction SilentlyContinue
if (-not $external) {
    $external = Get-Command nullclaw -ErrorAction SilentlyContinue
}

if ($external) {
    Write-Host "[NeoOptimize NullClaw] External CLI: $($external.Source)"
} else {
    Write-Host "[NeoOptimize NullClaw] External CLI: not installed. Using bundled read-only bridge."
}

if ($Onboard) {
    & $Bridge onboard
} else {
    & $Bridge status
    & $Bridge doctor
}
