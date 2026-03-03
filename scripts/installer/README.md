NeoOptimize installer (Inno Setup)

How to build (local):

1. Publish app:

```powershell
dotnet publish dotnet/NeoOptimize.App/NeoOptimize.App.csproj -c Release -o dotnet\NeoOptimize.App\bin\Release\net8.0-windows\publish
```

2. Open `neooptimize_inno.iss` in Inno Setup Compiler and build the installer. Adjust `SetupIconFile` and `Source` paths if your publish output differs.

Recommendations:
- Keep model downloads separate from base installer; provide an optional model-pack installer or on-demand download.
- Add EULA dialog and version checks in the script for GA.
