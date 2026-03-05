NeoOptimize - Installation & Development Prerequisites
===================================================

This file lists the recommended prerequisites and a short checklist to set up a development environment for NeoOptimize on Windows.

Required
--------
- Windows 10 (19041) or later
- .NET SDK 8.x (for `net8.0-windows` projects)
- Visual Studio 2022 (or Build Tools) with the following components:
  - MSBuild
  - C++ build tools (MSVC) — required to build the native Engine (optional if you only work on UI)
- Windows App SDK (WinApp SDK) 1.4.x for WinUI 3 projects

Optional but recommended
------------------------
- Git
- Winget for easy package installs

Quick install suggestions (using `winget`)

Run these commands in an elevated PowerShell prompt:

```powershell
winget install --id Microsoft.DotNet.SDK.8 -e
winget install --id Microsoft.VisualStudio.2022.BuildTools -e
```

For Windows App SDK download and installer, see:
https://learn.microsoft.com/windows/apps/windows-app-sdk/

Using the helper scripts
------------------------
- `scripts\check_prereqs.ps1` — run this to verify critical dependencies.
- `scripts\build.ps1` — runs the prereq check then restores and attempts to build all `.csproj` files.

Notes
-----
- If you plan to build the native C++ engine (`NeoOptimize.Engine`), ensure the C++ workload is installed in Visual Studio and `cl.exe` is on PATH (or build from a Developer Command Prompt).
- The UI project targets `net8.0-windows10.0.19041.0` and requires Windows App SDK to run correctly.

If you want, I can:

- Add a CI workflow that installs prerequisites and builds the solution in GitHub Actions.
- Add a convenience script that attempts to auto-install common components (requires admin and winget).
