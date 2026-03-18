; ============================================================
; NeoOptimize Installer (Inno Setup 6.3+)
; Diperbarui: 2026-03-18  ΓÇö Production Release
;
; Build (PowerShell):
;   $env:NEOOPTIMIZE_APP_SOURCE = "D:\NeoOptimize\client_windows\NeoOptimize\src\NeoOptimize.App\bin\Release\net8.0-windows\publish"
;   & "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" ".\installer\NeoOptimize.iss"
;
; Untuk signing jalankan sesudah build:
;   signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /a ".\artifacts\NeoOptimize-Setup-1.1.0.exe"
; ============================================================

#define AppName      "NeoOptimize"
#define AppExeName   "NeoOptimize.App.exe"
#define AppVersion   "1.1.0"
#define AppPublisher "NeoOptimize Team"
#define AppUrl       "https://github.com/NeoOptimize/NeoOptimize"
#define EngineDir    "D:\NeoOptimize\NeoOptimize.App\NeoOptimize.Engine"

#define AppSource GetEnv('NEOOPTIMIZE_APP_SOURCE')
#if AppSource == ""
  #define AppSource "D:\NeoOptimize\client_windows\NeoOptimize\src\NeoOptimize.App\bin\Release\net8.0-windows\publish"
#endif

; ΓöÇΓöÇ Setup metadata ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
[Setup]
AppId={{A8B9F5C3-4C5E-4B60-9B18-NEOOPTIMIZEV110}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
AppUpdatesURL={#AppUrl}
DefaultDirName={autopf}\{#AppName}
DisableDirPage=no
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\artifacts
OutputBaseFilename=NeoOptimize-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=admin
WizardStyle=modern
SetupIconFile=resources\neooptimize.ico
LicenseFile=resources\EULA.txt
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
MinVersion=10.0.19041

; ΓöÇΓöÇ Languages ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "id"; MessagesFile: "compiler:Languages\Indonesian.isl"

; ΓöÇΓöÇ Tasks (optional checkboxes) ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
[Tasks]
Name: "desktopicon";    Description: "Buat ikon di &Desktop";         GroupDescription: "Ikon tambahan:"; Flags: unchecked
Name: "startupicon";   Description: "Mulai otomatis saat login";      GroupDescription: "Startup:";       Flags: unchecked
Name: "scheduletasks"; Description: "Daftarkan jadwal tugas otomatis (SmartBoost, IntegrityScan)"; GroupDescription: "Automation:"; Flags: checked

; ΓöÇΓöÇ Files ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
[Files]
; ---- Main application -------------------------------------------------------
Source: "{#AppSource}\*";                 DestDir: "{app}";           Flags: recursesubdirs createallsubdirs ignoreversion

; ---- C++ Engine DLL ---------------------------------------------------------
Source: "{#EngineDir}\bin\Release\NeoOptimize.Engine.dll"; DestDir: "{app}"; Flags: ignoreversion; Check: FileExists(ExpandConstant('{#EngineDir}\bin\Release\NeoOptimize.Engine.dll'))

; ---- Bloatware database (updated independently) -----------------------------
Source: "..\client_windows\NeoOptimize\src\NeoOptimize.App\bloatware.json"; DestDir: "{app}"; Flags: ignoreversion

; ---- Permissions & config ---------------------------------------------------
Source: "..\permissions\neooptimize\permissions.json"; DestDir: "{app}\permissions\neooptimize"; Flags: ignoreversion
Source: "..\permissions\engine optimize\*";            DestDir: "{app}\permissions\engine optimize"; Flags: recursesubdirs createallsubdirs ignoreversion

; ---- Models directory (placeholder ΓÇö filled by ModelDownloadService) ---------
Source: "resources\models\.gitkeep"; DestDir: "{localappdata}\NeoOptimize\models"; Flags: ignoreversion onlyifdestfileexists; Check: False; DestName: ".gitkeep"

; ---- Legal & support files --------------------------------------------------
Source: "resources\CONSENT.txt";    DestDir: "{app}"; Flags: ignoreversion
Source: "resources\PRIVACY.txt";    DestDir: "{app}"; Flags: ignoreversion
Source: "scripts\NeoOptimize-Uninstall.ps1"; DestDir: "{commonappdata}\NeoOptimize"; Flags: ignoreversion uninsneveruninstall

; ΓöÇΓöÇ Registry ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
[Registry]
; Run on startup (optional ΓÇö only if user checked Task "startupicon")
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "NeoOptimize"; ValueData: """{app}\{#AppExeName}"" --minimized"; Flags: uninsdeletevalue; Tasks: startupicon

; Add to Apps & Features
Root: HKLM; Subkey: "Software\{#AppPublisher}\{#AppName}"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\{#AppPublisher}\{#AppName}"; ValueType: string; ValueName: "Version";     ValueData: "{#AppVersion}"

; ΓöÇΓöÇ Icons ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
[Icons]
Name: "{group}\NeoOptimize";              Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\neooptimize.ico"
Name: "{group}\Hapus NeoOptimize";        Filename: "{uninstallexe}"
Name: "{commondesktop}\NeoOptimize";      Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\neooptimize.ico"; Tasks: desktopicon

; ΓöÇΓöÇ Post-install run ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
[Run]
; Register Windows Task Scheduler tasks (only if user checked the task)
Filename: "{sys}\schtasks.exe"; Parameters: "/Create /TN ""\NeoOptimize\NeoOptimize_SmartBoost""   /SC MINUTE /MO 30 /TR """"""{app}\{#AppExeName}"" --background smart-boost"""""" /RL HIGHEST /F"; StatusMsg: "Mendaftarkan SmartBoost scheduler..."; Flags: runhidden; Tasks: scheduletasks
Filename: "{sys}\schtasks.exe"; Parameters: "/Create /TN ""\NeoOptimize\NeoOptimize_SmartOptimize"" /SC HOURLY  /MO 12  /TR """"""{app}\{#AppExeName}"" --background smart-optimize"""""" /RL HIGHEST /F"; StatusMsg: "Mendaftarkan SmartOptimize scheduler..."; Flags: runhidden; Tasks: scheduletasks
Filename: "{sys}\schtasks.exe"; Parameters: "/Create /TN ""\NeoOptimize\NeoOptimize_IntegrityScan"" /SC DAILY   /ST 02:00 /TR """"""{app}\{#AppExeName}"" --background integrity-scan"""""" /RL HIGHEST /F"; StatusMsg: "Mendaftarkan IntegrityScan scheduler..."; Flags: runhidden; Tasks: scheduletasks

; Launch app after install
Filename: "{app}\{#AppExeName}"; Description: "Buka NeoOptimize sekarang"; Flags: nowait postinstall skipifsilent shellexec

; ΓöÇΓöÇ On uninstall ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
[UninstallRun]
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""\NeoOptimize\NeoOptimize_SmartBoost""   /F"; Flags: runhidden
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""\NeoOptimize\NeoOptimize_SmartOptimize"" /F"; Flags: runhidden
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""\NeoOptimize\NeoOptimize_IntegrityScan"" /F"; Flags: runhidden
Filename: "{cmd}"; Parameters: "/C powershell -NoProfile -ExecutionPolicy Bypass -File ""{commonappdata}\NeoOptimize\NeoOptimize-Uninstall.ps1"" -InstallDir ""{app}"""; Flags: runhidden

; ΓöÇΓöÇ Custom Code ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
[Code]
// ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ Variables ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
var
  ConsentPage: TWizardPage;
  ConsentMemo: TNewMemo;
  AllPermissionsCheck: TNewCheckBox;
  UninstallFeedback: String;

// ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ .NET 8 Desktop Runtime check ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
function IsDotNet8DesktopInstalled: Boolean;
var
  Output: String;
  ResultCode: Integer;
begin
  // Try "dotnet --list-runtimes" ΓÇö look for Microsoft.WindowsDesktop.App 8.x
  Result := False;
  if Exec(ExpandConstant('{sys}\cmd.exe'),
          '/C dotnet --list-runtimes | findstr "Microsoft.WindowsDesktop.App 8."',
          '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Result := (ResultCode = 0);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not IsDotNet8DesktopInstalled then
  begin
    if MsgBox('.NET 8 Desktop Runtime belum terinstall.' + #13#10 +
              'NeoOptimize membutuhkan .NET 8 Desktop Runtime x64.' + #13#10 + #13#10 +
              'Buka halaman download sekarang?',
              mbConfirmation, MB_YESNO) = idYes then
      ShellExecAsOriginalUser('open',
        'https://dotnet.microsoft.com/download/dotnet/8.0',
        '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
    // Don't block install ΓÇö user may have a custom path
  end;
end;

// ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ Consent page ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
function BoolToJson(Value: Boolean): String;
begin
  if Value then Result := 'true' else Result := 'false';
end;

procedure InitializeWizard;
var
  ConsentText: String;
begin
  ConsentPage := CreateCustomPage(wpLicense, 'Persetujuan & Izin',
    'Pilih izin yang Anda berikan kepada NeoOptimize dan Neo AI.');

  ConsentMemo := TNewMemo.Create(ConsentPage);
  ConsentMemo.Parent := ConsentPage.Surface;
  ConsentMemo.Left   := ScaleX(0);
  ConsentMemo.Top    := ScaleY(0);
  ConsentMemo.Width  := ConsentPage.SurfaceWidth;
  ConsentMemo.Height := ScaleY(120);
  ConsentMemo.ReadOnly   := True;
  ConsentMemo.ScrollBars := ssVertical;
  ConsentMemo.WordWrap   := True;
  ConsentMemo.Font.Name  := 'Segoe UI';
  ConsentMemo.Font.Size  := 9;

  ConsentText :=
    'NeoOptimize memerlukan beberapa izin sistem agar dapat berfungsi dengan baik:' + #13#10 +
    '  ΓÇó Telemetri & Diagnostik  ΓÇö membantu kami memperbaiki bug.' + #13#10 +
    '  ΓÇó Maintenance otomatis    ΓÇö SmartBoost & Optimizer berjalan di background.' + #13#10 +
    '  ΓÇó Remote control          ΓÇö untuk fitur cloud AI & sinkronisasi.' + #13#10 +
    '  ΓÇó Lokasi (opsional)       ΓÇö hanya untuk fitur regional.' + #13#10 + #13#10 +
    'Data tidak pernah dijual. Lihat PRIVACY.txt untuk detail lengkap.' + #13#10 +
    'Anda dapat mengubah izin kapan saja dari menu Settings > Privacy.';
  ConsentMemo.Lines.Text := ConsentText;

  AllPermissionsCheck := TNewCheckBox.Create(ConsentPage);
  AllPermissionsCheck.Parent  := ConsentPage.Surface;
  AllPermissionsCheck.Left    := ScaleX(0);
  AllPermissionsCheck.Top     := ConsentMemo.Top + ConsentMemo.Height + ScaleY(10);
  AllPermissionsCheck.Width   := ConsentPage.SurfaceWidth;
  AllPermissionsCheck.Caption := 'Saya menyetujui semua perizinan yang dibutuhkan NeoOptimize';
  AllPermissionsCheck.Checked := True;
end;

procedure WriteConsentFile;
var
  ConsentDir, ConsentPath, Json: String;
begin
  ConsentDir := ExpandConstant('{commonappdata}\NeoOptimize');
  ForceDirectories(ConsentDir);
  ConsentPath := ConsentDir + '\consent.json';
  Json :=
    '{' + #13#10 +
    '  "accepted":     ' + BoolToJson(AllPermissionsCheck.Checked) + ',' + #13#10 +
    '  "telemetry":    ' + BoolToJson(AllPermissionsCheck.Checked) + ',' + #13#10 +
    '  "diagnostics":  ' + BoolToJson(AllPermissionsCheck.Checked) + ',' + #13#10 +
    '  "maintenance":  ' + BoolToJson(AllPermissionsCheck.Checked) + ',' + #13#10 +
    '  "remoteControl":' + BoolToJson(AllPermissionsCheck.Checked) + ',' + #13#10 +
    '  "autoExecution":' + BoolToJson(AllPermissionsCheck.Checked) + ',' + #13#10 +
    '  "location":     ' + BoolToJson(AllPermissionsCheck.Checked) + ',' + #13#10 +
    '  "camera":       ' + BoolToJson(AllPermissionsCheck.Checked) + ',' + #13#10 +
    '  "microphone":   false,' + #13#10 +
    '  "consentVersion":"1.1",' + #13#10 +
    '  "acceptedAt":   "' + GetDateTimeString('yyyy/mm/dd hh:nn:ss', '-', ':') + '"' + #13#10 +
    '}' + #13#10;
  SaveStringToFile(ConsentPath, Json, False);
end;

// Create empty models directory so ModelDownloadService finds it
procedure EnsureModelsDirectory;
var
  ModelsDir: String;
begin
  ModelsDir := ExpandConstant('{localappdata}\NeoOptimize\models');
  ForceDirectories(ModelsDir);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    WriteConsentFile;
    EnsureModelsDirectory;
  end;
end;

// ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ Uninstall feedback ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
function AskForUninstallFeedback(var Feedback: String): Boolean;
var
  Form: TSetupForm;
  LabelText: TNewStaticText;
  MemoInput: TNewMemo;
  SendButton, SkipButton: TNewButton;
  ResultCode: Integer;
begin
  Result := False;
  Form := CreateCustomForm(ScaleX(440), ScaleY(260), False, True);
  try
    Form.Caption := 'Feedback Sebelum Uninstall';
    Form.Position := poScreenCenter;

    LabelText := TNewStaticText.Create(Form);
    LabelText.Parent  := Form;
    LabelText.Caption := 'Ceritakan apa yang ingin Anda perbaiki (opsional):';
    LabelText.Left    := ScaleX(12);
    LabelText.Top     := ScaleY(12);
    LabelText.Width   := Form.ClientWidth - ScaleX(24);

    MemoInput := TNewMemo.Create(Form);
    MemoInput.Parent := Form;
    MemoInput.Left   := ScaleX(12);
    MemoInput.Top    := LabelText.Top + LabelText.Height + ScaleY(8);
    MemoInput.Width  := Form.ClientWidth - ScaleX(24);
    MemoInput.Height := ScaleY(140);

    SendButton := TNewButton.Create(Form);
    SendButton.Parent      := Form;
    SendButton.Caption     := 'Kirim';
    SendButton.ModalResult := mrOk;
    SendButton.Left        := Form.ClientWidth - ScaleX(175);
    SendButton.Top         := MemoInput.Top + MemoInput.Height + ScaleY(10);
    SendButton.Width       := ScaleX(80);

    SkipButton := TNewButton.Create(Form);
    SkipButton.Parent      := Form;
    SkipButton.Caption     := 'Lewati';
    SkipButton.ModalResult := mrCancel;
    SkipButton.Left        := Form.ClientWidth - ScaleX(85);
    SkipButton.Top         := SendButton.Top;
    SkipButton.Width       := ScaleX(75);

    Form.ActiveControl := MemoInput;
    if Form.ShowModal = mrOk then
    begin
      Feedback := Trim(MemoInput.Text);
      Result   := True;
    end;
  finally
    Form.Free;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  FeedbackPath: String;
begin
  if CurUninstallStep = usUninstall then
    if not UninstallSilent then
      if MsgBox('Kirim feedback sebelum uninstall NeoOptimize?', mbConfirmation, MB_YESNO) = idYes then
      begin
        UninstallFeedback := '';
        if AskForUninstallFeedback(UninstallFeedback) then
        begin
          FeedbackPath := ExpandConstant('{commonappdata}\NeoOptimize\uninstall_feedback.txt');
          SaveStringToFile(FeedbackPath, UninstallFeedback, False);
        end;
      end;
end;
