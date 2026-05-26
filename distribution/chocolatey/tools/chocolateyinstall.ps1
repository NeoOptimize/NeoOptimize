$ErrorActionPreference = 'Stop'

$packageName = 'neooptimize'
$url64 = 'https://github.com/NeoOptimize/NeoOptimize/releases/download/v1.0.6/NeoOptimize.exe'
$checksum64 = '9a1060bdab1ea370e7820ecdd1376134dd68b24a01fe7d93d1f3ea5731ee8bb5'

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
