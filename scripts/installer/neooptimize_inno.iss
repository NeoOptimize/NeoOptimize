; Inno Setup script for NeoOptimize (basic). Adjust paths before building.
[Setup]
AppName=NeoOptimize
AppVersion=1.0.0
DefaultDirName={autopf}\NeoOptimize
DefaultGroupName=NeoOptimize
OutputBaseFilename=NeoOptimize-Setup-1.0.0
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
SetupIconFile=..\..\dotnet\NeoOptimize.App\Assets\logo.ico

[Files]
; publish output path - ensure "dotnet publish" output is placed here before building installer
Source: "..\..\dotnet\NeoOptimize.App\bin\Release\net8.0-windows\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\NeoOptimize"; Filename: "{app}\NeoOptimize.App.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Assets\logo.ico"
Name: "{group}\Uninstall NeoOptimize"; Filename: "{uninstallexe}"

[Run]
; Start app after install
Filename: "{app}\NeoOptimize.App.exe"; Description: "Launch NeoOptimize"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\models"

; Notes:
; - This is a minimal installer script. Adjust to include licensing files, EULA acceptance, and optional model packages.
; - For large model bundles, provide separate model packages or download-on-demand to keep installer small.
