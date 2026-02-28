# Lightweight registry cleanup script: lists suspicious Run keys for manual review.
# DO NOT auto-delete registry keys; this script reports entries only.

$runPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")
Write-Output "Scanning Run keys for HKLM/HKCU..."
foreach ($rp in $runPaths) {
  try {
    $vals = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
    foreach ($v in $vals) {
      $val = (Get-ItemProperty -Path $rp -Name $v -ErrorAction SilentlyContinue).$v
      Write-Output "$rp - $v => $val"
    }
  } catch {
    Write-Output "ERR reading $rp: $_"
  }
}
Write-Output "Finished. Review entries and delete manually if needed."
