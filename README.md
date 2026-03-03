# NeoOptimize (Windows Offline)

NeoOptimize is a native Windows optimization application built with C# WPF
(.NET 8). The active codebase is under `dotnet/`.

## Scope

- Windows-only native desktop app (offline-first).
- AI module is advisor-only (no direct system mutation).
- System execution remains in native core engine with admin context.

## Repository Layout

- `dotnet/NeoOptimize.slnx` - main .NET solution
- `dotnet/NeoOptimize.App` - WPF UI
- `dotnet/NeoOptimize.Core` - cleaner/optimizer/system/security core logic
- `dotnet/NeoOptimize.Services` - update/localization/remote assist services
- `dotnet/NeoOptimize.AIAdvisor` - Ollama/GPT4All/rule-based adapters
- `dotnet/NeoOptimize.Installer` - WiX MSI installer assets
- `.github/workflows/dotnet-installer.yml` - CI build/test/installer workflow

## Prerequisites

- Windows 10/11
- .NET SDK 8.x
- PowerShell 7+
- WiX CLI 4.x (`dotnet tool install --global wix --version 4.*`)

## Build, Test, Run

```powershell
dotnet build .\dotnet\NeoOptimize.slnx
dotnet test .\dotnet\NeoOptimize.slnx
dotnet run --project .\dotnet\NeoOptimize.App\NeoOptimize.App.csproj
```

## Build MSI Installer (v1.0.0)

```powershell
.\dotnet\scripts\package-installers.ps1 -Variant both -ProductVersion 1.0.0
```

Outputs:

- `dotnet/out/installers/NeoOptimize-CoreOnly.msi`
- `dotnet/out/installers/NeoOptimize-CorePlusAI.msi`

## Release Checklist

See `RELEASE_CHECKLIST_v1.0.md` for final validation, tagging, and GitHub
release steps.
