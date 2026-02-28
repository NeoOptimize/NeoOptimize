# Lightweight disk optimizer: runs defrag analysis (no auto-defrag by default)
param(
  [switch]$RunDefrag
)

# List logical drives
$drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ge 1 }
foreach ($d in $drives) {
  Write-Output "Drive: $($d.Name): - Free: $([math]::Round($d.Free/1GB,2)) GB"
  Write-Output "Running defrag analysis for $($d.Name):"
  try {
    $res = defrag "$($d.Name):" -a 2>&1
    Write-Output $res
    if ($RunDefrag) {
      Write-Output "Executing defrag for $($d.Name):"
      defrag "$($d.Name):" -w
    }
  } catch {
    Write-Output "ERR: $_"
  }
}
Write-Output "Done"
