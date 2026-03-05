# NeoOptimize — Scaffold

This workspace contains a minimal scaffold for NeoOptimize V1.0.

What was added:
- `NeoOptimize.Engine` — C++ DLL skeleton with simple exported functions (`NO_GetVersion`, `NO_StartScan`, `NO_Stop`).
- `NeoOptimize.UI.ConsoleTest` — .NET console application that P/Invokes into the engine to demonstrate interop.

Next steps:
- Open the folder in Visual Studio (recommended) and create a `NeoOptimize.UI` WinUI 3 project using the Windows App SDK templates, then integrate the `CleanerService` P/Invoke wrappers with `NeoOptimize.Engine` exports.
- Replace engine stubs with real scanning/cleanup implementations from the blueprint attachments.


Troubleshooting native DLL load
 - If you see: "Unable to load DLL 'NeoOptimize.Engine.dll' or one of its dependencies" then the native DLL is not present
	in the managed app probing paths or a native dependency is missing.
 - Quick checks:
	1. Build the engine: open an x64 Developer PowerShell and run:

```
.\build-engine.ps1
```

	2. Verify the produced `NeoOptimize.Engine.dll` is copied into the managed app output, for example:

```
dir NeoOptimize.UI.ConsoleTest\bin\Debug\net8.0\NeoOptimize.Engine.dll
```

	3. Use the included `NeoOptimize.DllLoadTester` to try loading the DLL from common locations and get `GetLastError` codes:

```
dotnet run --project NeoOptimize.DllLoadTester
```

	4. If the DLL still fails to load, common causes:
	  - Platform mismatch (build the native DLL for x64 if running 64-bit .NET host).
	  - Missing Visual C++ runtime for the toolset used to build the DLL. Install the Visual C++ Redistributable or build with static CRT.
	  - DLL is present but depends on another DLL that's missing; use tools like `dumpbin /dependents` or `Dependencies` (third-party) to inspect.

Next steps
 - Run `build-engine.ps1`, then run the `NeoOptimize.DllLoadTester` and the console test. If you paste the `DllLoadTester` output here I will interpret the `GetLastError` codes and advise next steps.

This scaffold is intentionally minimal to provide a safe starting point for iterative development.

See `NeoOptimize/Blueprints` for design docs and feature lists.
