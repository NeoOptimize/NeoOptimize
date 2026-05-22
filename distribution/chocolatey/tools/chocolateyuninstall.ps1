$ErrorActionPreference = 'Stop'

$packageName = 'neooptimize'
$uninstaller = Join-Path ${env:ProgramFiles} 'NeoOptimize\Uninstall.exe'

if (Test-Path $uninstaller) {
  $packageArgs = @{
    packageName    = $packageName
    fileType       = 'exe'
    silentArgs     = '/S'
    validExitCodes = @(0)
    file           = $uninstaller
  }

  Uninstall-ChocolateyPackage @packageArgs
}

