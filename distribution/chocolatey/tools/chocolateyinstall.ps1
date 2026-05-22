$ErrorActionPreference = 'Stop'

$packageName = 'neooptimize'
$url64 = 'https://github.com/NeoOptimize/NeoOptimize/releases/download/v1.0.0/NeoOptimize.exe'
$checksum64 = '70864f39c4d111c4071061381f0127f30afa406fda95f6e02ad52293635937af'

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

