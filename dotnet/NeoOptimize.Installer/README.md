# NeoOptimize Installer (WiX v4)

`InstallerConfig.wxs` builds a simple install flow (no feature selection page) with:

- MIT license agreement page
- install directory page
- desktop shortcut + start menu shortcut
- `perMachine` scope

## Build

1. Install WiX CLI once:
   - `dotnet tool install --global wix --version 4.*`
2. Package both variants:
   - `..\scripts\package-installers.ps1 -Variant both -ProductVersion 1.0.0`

Outputs:

- `..\out\installers\NeoOptimize-CoreOnly.msi`
- `..\out\installers\NeoOptimize-CorePlusAI.msi`

## Variant model

Installer UI does not ask optional components to avoid user confusion.
Variant is decided at build time:

- `CoreOnly`: app + core modules only.
- `CorePlusAI`: app + core modules + bundled AI runtime payload.

## Release hardening

- Sign `NeoOptimize.App.exe` and both MSI files using Authenticode (`signtool`)
  before GitHub release.
- Unsigned binaries may still trigger SmartScreen reputation warnings.
