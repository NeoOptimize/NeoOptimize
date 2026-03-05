$ms = Get-ChildItem 'C:\Program Files (x86)\MSBuild' -Filter MSBuild.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if ($ms -ne $null) {
    Write-Output "Found MSBuild: $ms"
    & $ms 'D:\NeoOptimize\NeoOptimize.Engine\NeoOptimize.Engine.vcxproj' /p:Configuration=Release /p:Platform=x64 /t:Build /m
} else {
    Write-Output 'msbuild-not-found'
}
