$candidates = @(
  'C:\BuildTools\MSBuild\Current\Bin\MSBuild.exe',
  'C:\BuildTools\MSBuild\15.0\Bin\MSBuild.exe',
  'C:\Program Files (x86)\Microsoft Visual Studio\BuildTools\MSBuild\Current\Bin\MSBuild.exe',
  'C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe',
  'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe',
  'C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe',
  'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
)

$found = $null
foreach ($p in $candidates) {
  if (Test-Path $p) { $found = $p; break }
}

if ($found) {
  Write-Output "Found MSBuild at: $found"
  & $found 'D:\NeoOptimize\NeoOptimize.Engine\NeoOptimize.Engine.vcxproj' /p:Configuration=Release /p:Platform=x64 /t:Build /m
} else {
  Write-Output 'msbuild-not-found'
}
