# NeoOptimize (Windows Offline)

NeoOptimize is a native Windows optimization app using C# WPF and .NET 8.
The active implementation is in the `dotnet/` solution.

## Project Structure

- `dotnet/NeoOptimize.slnx` - main .NET solution
- `dotnet/NeoOptimize.App` - WPF UI layer
- `dotnet/NeoOptimize.Core` - cleaner/optimizer/system/security core
- `dotnet/NeoOptimize.Services` - update/localization/remote-assist services
- `dotnet/NeoOptimize.AIAdvisor` - local AI advisor adapters (advisor-only)
- `dotnet/NeoOptimize.Installer` - WiX installer assets
- `.github/workflows/dotnet-installer.yml` - CI build/test/package for .NET

## Build and Run

```powershell
dotnet build .\dotnet\NeoOptimize.slnx
dotnet test .\dotnet\NeoOptimize.slnx
dotnet run --project .\dotnet\NeoOptimize.App\NeoOptimize.App.csproj
```

## Package MSI Installer

```powershell
.\dotnet\scripts\package-installers.ps1 -Variant both -ProductVersion 1.0.0
```
