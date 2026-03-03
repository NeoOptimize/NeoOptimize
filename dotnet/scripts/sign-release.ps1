param(
    [Parameter(Mandatory = $true)]
    [string]$CertificatePfxPath,

    [Parameter(Mandatory = $true)]
    [string]$CertificatePassword,

    [string]$TimestampUrl = "http://timestamp.digicert.com"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-SignTool {
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $wackSignTool = "${env:ProgramFiles(x86)}\Windows Kits\10\App Certification Kit\signtool.exe"
    if (Test-Path $wackSignTool) {
        return $wackSignTool
    }

    $kitRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    if (-not (Test-Path $kitRoot)) {
        throw "signtool.exe not found and Windows Kits bin path does not exist: $kitRoot"
    }

    $candidate = Get-ChildItem -Path $kitRoot -Filter signtool.exe -Recurse |
        Where-Object { $_.FullName -match "\\x64\\signtool\.exe$" } |
        Sort-Object FullName -Descending |
        Select-Object -First 1

    if (-not $candidate) {
        throw "signtool.exe was not found under $kitRoot"
    }

    return $candidate.FullName
}

if (-not (Test-Path $CertificatePfxPath)) {
    throw "Certificate file not found: $CertificatePfxPath"
}

$targets = @(
    ".\dotnet\out\publish\NeoOptimize.App.exe",
    ".\dotnet\out\installers\NeoOptimize-CoreOnly.msi",
    ".\dotnet\out\installers\NeoOptimize-CorePlusAI.msi"
)

foreach ($target in $targets) {
    if (-not (Test-Path $target)) {
        throw "Signing target missing: $target"
    }
}

$signtool = Resolve-SignTool
Write-Host "Using signtool: $signtool"

foreach ($target in $targets) {
    Write-Host "Signing $target"
    & $signtool sign `
        /fd SHA256 `
        /f $CertificatePfxPath `
        /p $CertificatePassword `
        /tr $TimestampUrl `
        /td SHA256 `
        $target

    if ($LASTEXITCODE -ne 0) {
        throw "signtool failed for $target"
    }

    $signature = Get-AuthenticodeSignature -FilePath $target
    if ($signature.Status -ne "Valid") {
        throw "Invalid signature status for $target => $($signature.Status)"
    }
}

Write-Host "All release binaries are signed and valid."
