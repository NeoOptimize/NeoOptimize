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

1. Publish app:
   - `dotnet publish ..\NeoOptimize.App\NeoOptimize.App.csproj -c Release -r win-x64 --self-contained false`
2. Prepare optional AI runtime files under `..\runtime\ai`.
3. Build MSI with WiX v4 toolchain.

## Feature selection at install time

Use MSI features:

- Core only:
  - `ADDLOCAL=CoreFeature`
- Core + AI Advisor:
  - `ADDLOCAL=CoreFeature,AiAdvisorFeature`

Keep code-signing enabled for both MSI and binaries.
