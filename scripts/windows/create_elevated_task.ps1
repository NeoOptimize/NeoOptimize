<#
Creates a scheduled task that runs the NeoOptimize backend on user logon with highest privileges.
Usage (PowerShell as Administrator):
  .\create_elevated_task.ps1 -InstallPath 'D:\NeoOptimize' -NodeExe 'C:\Program Files\nodejs\node.exe'

This is a best-effort helper. It uses Windows Scheduled Tasks to run the backend elevated.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)] [string]$InstallPath,
  [Parameter(Mandatory=$false)] [string]$NodeExe = 'node'
)

if (-not (Test-Path $InstallPath)) { Write-Error "Install path not found: $InstallPath"; exit 1 }

$taskName = 'NeoOptimize_Backend'
$action = "`"$NodeExe`" `"$InstallPath\\backend\\server.js`" 

Write-Output "Creating scheduled task '$taskName' to run: $action"

try {
  schtasks /Create /F /RL HIGHEST /SC ONLOGON /TN $taskName /TR $action | Out-Null
  Write-Output "Task created. To remove: schtasks /Delete /TN $taskName /F"
} catch {
  Write-Error "Failed to create scheduled task: $_"
  exit 2
}

Write-Output "Done. The backend will start at next logon with elevated privileges."
