# Clean temp files older than 7 days in the Windows temp folders (user + system)
param(
  [int]$Days = 7,
  [switch]$WhatIf
)

function SafeRemove($file) {
  try {
    if ($WhatIf) {
      Write-Output "WHATIF: Remove $file"
    } else {
      Remove-Item -LiteralPath $file -Force -Recurse -ErrorAction SilentlyContinue
      Write-Output "Removed: $file"
    }
  } catch {
    Write-Output "ERR: $_"
  }
}

$paths = @($env:TEMP, "$env:windir\Temp") | Where-Object { Test-Path $_ }
Write-Output "Scanning: $($paths -join ', ')"
foreach ($p in $paths) {
  Get-ChildItem -Path $p -Force -ErrorAction SilentlyContinue | Where-Object {
    ($_.LastWriteTime -lt (Get-Date).AddDays(-$Days)) -and -not ($_.PSIsContainer -and (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 2000)
  } | ForEach-Object {
    SafeRemove $_.FullName
  }
}
Write-Output "Done"
