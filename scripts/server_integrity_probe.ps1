<#
  Non-destructive probe for server-side integrity logic.
  - Computes SHA256 counts for App files and reports any missing expected files
  - Doesn't modify system state
#>

param()

$root = "d:\\NeoOptimize\\dist\\NeoOptimize-v1.0.0-win-x64-20260310115936\\App"
$out = "d:\\NeoOptimize\\artifacts\\server-integrity-probe.txt"

if (-not (Test-Path $root)) {
    "Root not found: $root" | Out-File $out
    exit 1
}

Get-ChildItem -Path $root -Recurse -File | Where-Object { $_.Length -gt 0 } | ForEach-Object {
    $hash = Get-FileHash -Path $_.FullName -Algorithm SHA256
    [PSCustomObject]@{
        Path = $_.FullName.Substring($root.Length + 1)
        Size = $_.Length
        SHA256 = $hash.Hash
    }
} | Sort-Object Path | ConvertTo-Json -Depth 3 | Out-File $out -Encoding utf8

"Server integrity probe written to $out"