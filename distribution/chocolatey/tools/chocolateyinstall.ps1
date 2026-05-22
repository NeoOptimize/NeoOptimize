$ErrorActionPreference = 'Stop'

$packageName = 'neooptimize'
$url64 = 'https://github.com/NeoOptimize/NeoOptimize/releases/download/v1.0.0/NeoOptimize.exe'
$checksum64 = 'b5a756017d3ea88a75187fe943a6c507f09c1c7a2c1455c2ccccaf3ccc55fc71'

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

