Quick test/run instructions

Prereqs:
- Windows with Visual Studio/MSBuild or dotnet 8 SDK installed

To build the UI and engine on a Windows dev machine (MSVC + MSBuild):
1. Open `NeoOptimize.sln` in Visual Studio and build `NeoOptimize.Engine` (x64) and `NeoOptimize.UI`.
2. Ensure the built `NeoOptimize.Engine.dll` is copied to the UI's output folder or added to PATH.

Test harness (quick check without full solution build):
- Build the test harness only:

```powershell
cd NeoOptimize.TestHarness
dotnet build -c Debug
cd ..\NeoOptimize.TestHarness\bin\Debug\net8.0
# Ensure NeoOptimize.Engine.dll is next to the exe (copy from NeoOptimize.Engine\bin\Release or the native build output)
.
```

- Run the harness to validate P/Invoke and callbacks.

GitHub Actions:
- A Windows build workflow was added at `.github/workflows/windows-build.yml` to build on push/pull_request.
