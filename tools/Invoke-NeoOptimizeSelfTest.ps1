#Requires -Version 5.1
<#
.SYNOPSIS
    Static production checks for NeoOptimize.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$required = @(
    "NeoOptimize.ps1",
    "NeoOptimizeAgent.ps1",
    "LAUNCH.bat",
    "CREATE_RESTORE_POINT.ps1",
    "config\NeoOptimize.AgentPolicy.json",
    "docs\ROADMAP_ALGORITMA.md",
    "tools\Invoke-WinTargetLabTest.sh",
    "lib\Common.ps1",
    "modules\01_Cleaner.ps1",
    "modules\02_Performance.ps1",
    "modules\03_Privacy.ps1",
    "modules\04_Network.ps1",
    "modules\05_Security.ps1",
    "modules\06_Services.ps1",
    "modules\07_Updates.ps1",
    "modules\08_Power.ps1"
)

$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)
    $script:failures.Add($Message)
}

foreach ($relative in $required) {
    $path = Join-Path $root $relative
    if (-not (Test-Path $path)) {
        Add-Failure "Missing required file: $relative"
    }
}

$scripts = Get-ChildItem -Path $root -Filter "*.ps1" -Recurse |
    Where-Object { $_.FullName -notmatch "\\backup\\" -and $_.FullName -notmatch "\\reports\\" }

foreach ($scriptFile in $scripts) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($err in $errors) {
        Add-Failure "Parse error: $($scriptFile.FullName):$($err.Extent.StartLineNumber) $($err.Message)"
    }
}

$dangerChecks = @(
    @{
        File = "modules\01_Cleaner.ps1"
        Pattern = '\$env:APPDATA\\Mozilla\\Firefox\\Profiles["'']?\s*;'
        Message = "Cleaner must not delete the whole Firefox Profiles directory."
    },
    @{
        File = "modules\03_Privacy.ps1"
        Pattern = 'remoteip\s*=\s*["'']?0\.0\.0\.0/0'
        Message = "Privacy must not create outbound firewall rules for 0.0.0.0/0."
    },
    @{
        File = "modules\07_Updates.ps1"
        Pattern = '\.\s+"\$PSScriptRoot\\07_Updates\.ps1"'
        Message = "Update preset must not recursively dot-source itself."
    },
    @{
        File = "modules\08_Power.ps1"
        Pattern = 'Select-String\s+"\(\\\{\[0-9a-f-\]\+\\\}\)"'
        Message = "Power custom-plan cleanup must parse GUIDs without braces."
    }
)

foreach ($check in $dangerChecks) {
    $path = Join-Path $root $check.File
    if (Test-Path $path) {
        $content = Get-Content -Path $path -Raw
        if ($content -match $check.Pattern) {
            Add-Failure $check.Message
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host "NeoOptimize self-test FAILED" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "NeoOptimize self-test PASSED" -ForegroundColor Green
Write-Host "Scripts checked: $($scripts.Count)"
exit 0
