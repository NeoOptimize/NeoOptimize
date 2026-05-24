$ErrorActionPreference = 'Stop'

$packageName = 'neooptimize'
$url64 = 'https://github.com/NeoOptimize/NeoOptimize/releases/download/v1.0.0/NeoOptimize.exe'
$checksum64 = 'cfff4ae2316a75106b9141c08ca0ef33220fa062c06d528d8784addce3abc7d3'

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
