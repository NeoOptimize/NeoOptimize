<#
PowerShell helper to sign one or more artifacts using a PFX file.
Usage:
  .\sign.ps1 -PfxPath .\cert.pfx -PfxPassword (Read-Host -AsSecureString) -Files .\artifacts\*.exe -TimestampUrl https://timestamp.digicert.com
#>

param(
    [Parameter(Mandatory=$true)] [string] $PfxPath,
    [Parameter(Mandatory=$true)] [string] $PfxPassword,
    [Parameter(Mandatory=$true)] [string[]] $Files,
    [string] $TimestampUrl = 'https://timestamp.digicert.com'
)

function Sign-File {
    param($file)
    Write-Host "Signing $file..."
    $signtool = 'signtool'
    & $signtool sign /f "$PfxPath" /p "$PfxPassword" /fd SHA256 /tr $TimestampUrl /td SHA256 "$file"
    if ($LASTEXITCODE -ne 0) { throw "signtool failed for $file" }
}

foreach ($f in $Files) {
    $matches = Get-ChildItem -Path $f -File -ErrorAction SilentlyContinue
    foreach ($m in $matches) { Sign-File $m.FullName }
}

Write-Host "Signing complete. Verify with Get-AuthenticodeSignature <file>."
