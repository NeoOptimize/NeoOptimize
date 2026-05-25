$ErrorActionPreference = 'Stop'

$packageName = 'neooptimize'
$url64 = 'https://github.com/NeoOptimize/NeoOptimize/releases/download/v1.0.4/NeoOptimize.exe'
$checksum64 = 'e1aa5037023f156fd3343962c1688bc6ea469153af146c53b6558370d47e286f'

$packageArgs = @{
  packageName    = $packageName
  fileType       = 'exe'
  url64bit       = $url64
  silentArgs     = '/S'
  validExitCodes = @(0)
  checksum64     = $checksum64
  checksumType64 = 'sha256'
}

Install-ChocolateyPackage @packageArgs
