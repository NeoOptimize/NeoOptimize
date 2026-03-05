$dll = 'D:\NeoOptimize\NeoOptimize.Engine\bin\Release\NeoOptimize.Engine.dll'
$destDirs = @(
    'D:\NeoOptimize\NeoOptimize.UI\bin\Release\net8.0-windows10.0.19041.0\win10-x64\',
    'D:\NeoOptimize\NeoOptimize.UI.ConsoleTest\bin\Release\net8.0\'
)

foreach ($d in $destDirs) {
    if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
    Copy-Item -Path $dll -Destination (Join-Path $d 'NeoOptimize.Engine.dll') -Force
    Write-Output "Copied to: $d"
}
