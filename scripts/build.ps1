<#
Simple build helper for NeoOptimize.
Runs prerequisite check then attempts to restore and build all .csproj files found.
#>
param()

Write-Host "Running prerequisite checks..."
.
Join-Path $PSScriptRoot 'check_prereqs.ps1'
try{
    & "$PSScriptRoot\check_prereqs.ps1"
    $status = $LASTEXITCODE
    if ($status -ne 0){ Write-Warn "Prereq check returned non-zero ($status). Continuing but build may fail." }
} catch { Write-Warn "Failed to run prerequisite check script." }

Write-Host "Restoring and building projects..."
$projects = Get-ChildItem -Path $PSScriptRoot\.. -Recurse -Filter *.csproj -ErrorAction SilentlyContinue
foreach ($p in $projects){
    Write-Host "\n== Building: $($p.FullName) =="
    dotnet restore "$($p.FullName)"
    dotnet build "$($p.FullName)" -c Debug
}

Write-Host "Build helper finished. Review output for errors."
