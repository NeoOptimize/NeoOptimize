# NeoOptimize Installer (WiX v4 Template)

`InstallerConfig.wxs` is prepared with two install features:

- `CoreFeature` (required)
- `AiAdvisorFeature` (optional)

## Source folders

- Core publish output:
  - `..\NeoOptimize.App\bin\Release\net8.0-windows\publish`
- Optional AI runtime/model bundle:
  - `..\runtime\ai`

Adjust these via preprocessor variables in `InstallerConfig.wxs`.

## Build flow (example)

1. Install WiX CLI (once):
   - `dotnet tool install --global wix --version 4.*`
2. Run packaging script:
   - `..\scripts\package-installers.ps1 -Variant both -ProductVersion 1.0.0`
3. MSI outputs:
   - `..\out\installers\NeoOptimize-CoreOnly.msi`
   - `..\out\installers\NeoOptimize-CorePlusAI.msi`

Optional:

- pass `-AiRuntimeSource <path>` to copy real offline AI runtime/model files before packaging.

## Feature selection at install time

Use MSI features:

- Core only:
  - `ADDLOCAL=CoreFeature`
- Core + AI Advisor:
  - `ADDLOCAL=CoreFeature,AiAdvisorFeature`

Keep code-signing enabled for both MSI and binaries.

## IncludeAi switch

`InstallerConfig.wxs` supports `IncludeAi` preprocessor define:

- `IncludeAi=0` -> build core-only package without AI feature.
- `IncludeAi=1` -> include optional AI feature and AI payload directory.
