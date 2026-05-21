; ═══════════════════════════════════════════════════════════════════
; NeoOptimize Client Setup — NSIS Installer Script
; Bundles: NeoOptimize.exe (optimizer) + NeoOptimize.Agent.exe (RMM)
; ═══════════════════════════════════════════════════════════════════

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "nsDialogs.nsh"

; ─── Metadata ─────────────────────────────────────────────────────
Name              "NeoOptimize Client"
OutFile           "NeoOptimize.exe"
Icon              "logo.ico"
UninstallIcon     "logo.ico"
InstallDir        "$PROGRAMFILES64\NeoOptimize"
InstallDirRegKey  HKLM "Software\NeoOptimize" "InstallDir"
RequestExecutionLevel admin
Unicode True

; ─── Version ──────────────────────────────────────────────────────
VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName"     "NeoOptimize Client"
VIAddVersionKey "CompanyName"     "Zenthralix Technologies"
VIAddVersionKey "LegalCopyright"  "© 2025 Zenthralix Technologies"
VIAddVersionKey "FileDescription" "NeoOptimize System Optimizer + RMM Agent"
VIAddVersionKey "FileVersion"     "1.0.0"

; ─── MUI Configuration ────────────────────────────────────────────
!define MUI_ABORTWARNING

!define MUI_WELCOMEPAGE_TITLE    "Welcome to NeoOptimize Setup"
!define MUI_WELCOMEPAGE_TEXT     "This will install NeoOptimize System Optimizer and the Remote Management Agent on your computer.$\n$\nNeoOptimize automatically optimizes your PC performance. The RMM Agent allows your IT administrator to monitor and maintain your system remotely."

!define MUI_FINISHPAGE_RUN           "$INSTDIR\program\NeoOptimize.exe"
!define MUI_FINISHPAGE_RUN_TEXT      "Launch NeoOptimize after install"
!define MUI_FINISHPAGE_SHOWREADME    "$INSTDIR\program\README_ZENTHRALIX_LAB.txt"
!define MUI_FINISHPAGE_SHOWREADME_TEXT "Open zenthralix-lab Show Me"
!define MUI_FINISHPAGE_TEXT          "NeoOptimize has been installed successfully.$\n$\nThe remote management agent will start automatically with Windows."

; ─── Pages ────────────────────────────────────────────────────────
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE        "LICENSE.txt"
Page custom ServerConfigPage ServerConfigPageLeave
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

; ─── Custom Server Configuration Page ─────────────────────────────
Var ServerUrlField
Var ServerUrl
Var Dialog

Function ServerConfigPage
  ; Skip if /SILENT or /SERVER= was passed
  ${GetParameters} $R0
  ${GetOptions} $R0 "/SERVER=" $R1
  ${If} $R1 != ""
    StrCpy $ServerUrl $R1
    Abort  ; Skip this page
  ${EndIf}

  nsDialogs::Create 1018
  Pop $Dialog
  ${If} $Dialog == error
    Abort
  ${EndIf}

  ${NSD_CreateLabel} 0 0 100% 20u "RMM Server Configuration"
  Pop $0
  SetCtlColors $0 0x00c6ff 0x060b14

  ${NSD_CreateLabel} 0 30u 100% 12u "Server URL (provided by your IT administrator):"
  Pop $0

  ${NSD_CreateText} 0 46u 100% 14u "http://192.168.122.1:3000"
  Pop $ServerUrlField

  ${NSD_CreateLabel} 0 66u 100% 24u "Enter the NeoOptimize RMM server address above. The agent will connect to this server for remote management."
  Pop $0

  nsDialogs::Show
FunctionEnd

Function ServerConfigPageLeave
  ${NSD_GetText} $ServerUrlField $ServerUrl
  ${If} $ServerUrl == ""
    StrCpy $ServerUrl "http://192.168.122.1:3000"
  ${EndIf}
FunctionEnd

Function StopExistingAgent
  DetailPrint "Stopping existing NeoOptimize RMM Agent service..."
  ExecWait 'sc stop "NeoOptimize RMM Agent"' $0
  Sleep 1500
  ExecWait 'taskkill /F /IM "NeoOptimize.Agent.exe"' $0
  Sleep 1000
  ExecWait 'sc delete "NeoOptimize RMM Agent"' $0
  Sleep 1500
FunctionEnd

Function StopExistingUi
  DetailPrint "Closing existing NeoOptimize UI process..."
  ExecWait 'taskkill /F /IM "NeoOptimize.exe"' $0
  Sleep 1000
FunctionEnd

; ─── Install ──────────────────────────────────────────────────────
Section "NeoOptimize Core" SEC01
  SectionIn RO  ; Required

  ; Upgrade-safe: release the old agent binary before overwriting it.
  Call StopExistingAgent
  Call StopExistingUi

  SetOutPath "$INSTDIR\program"
  SetOverwrite on

  ; Remove bundled content from older builds before copying the current
  ; distribution payload. Runtime logs/reports are recreated below.
  RMDir /r "$INSTDIR\program\modules"
  RMDir /r "$INSTDIR\program\lib"
  RMDir /r "$INSTDIR\program\assets"
  RMDir /r "$INSTDIR\program\config"
  RMDir /r "$INSTDIR\program\models"
  RMDir /r "$INSTDIR\program\datasets"
  RMDir /r "$INSTDIR\program\docs"
  Delete "$INSTDIR\program\NeoOptimize.exe"

  ; Core files
  File "bin\NeoOptimize.exe"
  File "signing.pub.pem"
  File "README_ZENTHRALIX_LAB.txt"
  File "NeoOptimize.UI.ps1"
  File "NeoOptimize.ps1"
  File "NeoOptimize.UpdateManager.ps1"
  File "NeoOptimize.AIAgent.ps1"
  File "NeoOptimize.Cloud.ps1"
  File "NeoOptimize.VoiceCommand.ps1"
  File "NeoOptimizeAgent.ps1"
  File "CREATE_RESTORE_POINT.ps1"
  File "ai_engine.py"
  File "VERSION.txt"

  ; PowerShell modules
  SetOutPath "$INSTDIR\program\modules"
  File /r "modules\*.*"

  SetOutPath "$INSTDIR\program\lib"
  File /r "lib\*.*"

  SetOutPath "$INSTDIR\program\assets"
  File /r "assets\*.*"

  SetOutPath "$INSTDIR\program\config"
  File /r "config\*.*"

  SetOutPath "$INSTDIR\program\models"
  File /r "models\*.*"

  SetOutPath "$INSTDIR\program\datasets"
  File /r "datasets\*.*"

  SetOutPath "$INSTDIR\program\docs"
  File /r "docs\*.*"

  SetOutPath "$INSTDIR\program"
  CreateDirectory "$INSTDIR\program\logs"
  CreateDirectory "$INSTDIR\program\reports"

  ; Uninstaller
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; Registry entries
  WriteRegStr HKLM "Software\NeoOptimize" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "Software\NeoOptimize" "ServerUrl"  "$ServerUrl"
  WriteRegStr HKLM "Software\NeoOptimize" "Version"    "1.0.0"

  ; Add to Programs & Features
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoOptimize" \
    "DisplayName"     "NeoOptimize Client"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoOptimize" \
    "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoOptimize" \
    "DisplayVersion"  "1.0.0"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoOptimize" \
    "Publisher"       "Zenthralix Technologies"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoOptimize" \
    "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoOptimize" \
    "NoRepair" 1

  ; Desktop shortcut for NeoOptimize
  CreateShortcut "$DESKTOP\NeoOptimize.lnk" "$INSTDIR\program\NeoOptimize.exe"

  ; Start menu
  CreateDirectory "$SMPROGRAMS\NeoOptimize"
  CreateShortcut "$SMPROGRAMS\NeoOptimize\NeoOptimize.lnk" "$INSTDIR\program\NeoOptimize.exe"
  CreateShortcut "$SMPROGRAMS\NeoOptimize\Show Me.lnk" "$WINDIR\System32\notepad.exe" "$INSTDIR\program\README_ZENTHRALIX_LAB.txt"
  CreateShortcut "$SMPROGRAMS\NeoOptimize\Uninstall.lnk"   "$INSTDIR\Uninstall.exe"

SectionEnd

; ─── Install RMM Agent as Windows Service ─────────────────────────
Section "RMM Agent Service" SEC02
  SectionIn RO  ; Required

  ; Ensure stale service state is cleared before recreating it.
  Call StopExistingAgent

  SetOutPath "$INSTDIR\agent"
  SetOverwrite on
  RMDir /r "$INSTDIR\agent\modules"
  RMDir /r "$INSTDIR\agent\lib"
  Delete "$INSTDIR\NeoOptimize.Agent.exe"
  Delete "$INSTDIR\agent\NeoOptimize.Agent.exe"

  File "bin\NeoOptimize.Agent.exe"
  File "signing.pub.pem"
  File "NeoOptimize_Uninstaller.ps1"

  SetOutPath "$INSTDIR\agent\modules"
  File /r "modules\*.*"

  SetOutPath "$INSTDIR\agent\lib"
  File /r "lib\*.*"

  SetOutPath "$INSTDIR\agent"
  CreateDirectory "$INSTDIR\agent\logs"

  ; Write appsettings.json with server URL from wizard
  FileOpen $0 "$INSTDIR\agent\appsettings.json" w
  FileWrite $0 '{$\n'
  FileWrite $0 '  "ServerUrl": "$ServerUrl",$\n'
  FileWrite $0 '  "ApiKey": "",$\n'
  FileWrite $0 '  "EnrollmentToken": "",$\n'
  FileWrite $0 '  "AllowInsecureTls": false,$\n'
  FileWrite $0 '  "Telemetry": {$\n'
  FileWrite $0 '    "IntervalSeconds": 1,$\n'
  FileWrite $0 '    "CollectDeviceCapabilities": true,$\n'
  FileWrite $0 '    "CollectApproxLocation": false,$\n'
  FileWrite $0 '    "CollectVerboseDiagnostics": false,$\n'
  FileWrite $0 '    "CollectCameraCapture": false,$\n'
  FileWrite $0 '    "CollectMicrophoneCapture": false,$\n'
  FileWrite $0 '    "CollectBiometricData": false$\n'
  FileWrite $0 '  },$\n'
  FileWrite $0 '  "Safety": {$\n'
  FileWrite $0 '    "SecureStorePath": "%ProgramData%\\NeoOptimize\\SecureStore",$\n'
  FileWrite $0 '    "CrashLoopThreshold": 2,$\n'
  FileWrite $0 '    "EnableLabCommands": true,$\n'
  FileWrite $0 '    "MaxMonitoringSeconds": 900,$\n'
  FileWrite $0 '    "RegistrySnapshotMaxDepth": 2,$\n'
  FileWrite $0 '    "RegistrySnapshotMaxKeys": 2500,$\n'
  FileWrite $0 '    "RegistrySnapshotMaxValues": 10000$\n'
  FileWrite $0 '  },$\n'
  FileWrite $0 '  "Serilog": {$\n'
  FileWrite $0 '    "MinimumLevel": { "Default": "Information", "Override": { "Microsoft": "Warning", "System": "Warning" } },$\n'
  FileWrite $0 '    "WriteTo": [{"Name": "Console"}, {"Name": "File", "Args": {"path": "logs/agent-.log", "rollingInterval": "Day", "retainedFileCountLimit": 7}}]$\n'
  FileWrite $0 '  }$\n'
  FileWrite $0 '}$\n'
  FileClose $0

  ; Install as Windows Service
  ExecWait 'sc create "NeoOptimize RMM Agent" binPath= "\"$INSTDIR\agent\NeoOptimize.Agent.exe\"" start= auto' $0
  ExecWait 'sc config "NeoOptimize RMM Agent" start= auto' $0
  ExecWait 'sc description "NeoOptimize RMM Agent" "Authorized NeoOptimize remote monitoring and maintenance agent."' $0
  ExecWait 'sc failure "NeoOptimize RMM Agent" reset= 60 actions= restart/5000/restart/10000/""/30000' $0
  ExecWait 'sc start "NeoOptimize RMM Agent"' $0

  ; Fallback: auto-start via Run registry key
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Run" \
    "NeoOptimizeAgent" '"$INSTDIR\agent\NeoOptimize.Agent.exe"'

SectionEnd

; ─── Uninstall ────────────────────────────────────────────────────
Section "Uninstall"

  ExecWait 'sc stop "NeoOptimize RMM Agent"'
  ExecWait 'sc delete "NeoOptimize RMM Agent"'
  Sleep 1000

  Delete "$INSTDIR\NeoOptimize.exe"
  Delete "$INSTDIR\NeoOptimize.Agent.exe"
  Delete "$INSTDIR\agent\NeoOptimize.Agent.exe"
  Delete "$INSTDIR\appsettings.json"
  Delete "$INSTDIR\README_ZENTHRALIX_LAB.txt"
  Delete "$INSTDIR\NeoOptimize.UI.ps1"
  Delete "$INSTDIR\NeoOptimize.ps1"
  Delete "$INSTDIR\NeoOptimize.AIAgent.ps1"
  Delete "$INSTDIR\NeoOptimize.Cloud.ps1"
  Delete "$INSTDIR\NeoOptimize.VoiceCommand.ps1"
  Delete "$INSTDIR\NeoOptimizeAgent.ps1"
  Delete "$INSTDIR\CREATE_RESTORE_POINT.ps1"
  Delete "$INSTDIR\ai_engine.py"
  Delete "$INSTDIR\VERSION.txt"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir  /r "$INSTDIR\modules"
  RMDir  /r "$INSTDIR\lib"
  RMDir  /r "$INSTDIR\assets"
  RMDir  /r "$INSTDIR\config"
  RMDir  /r "$INSTDIR\models"
  RMDir  /r "$INSTDIR\datasets"
  RMDir  /r "$INSTDIR\docs"
  RMDir  /r "$INSTDIR\reports"
  RMDir  /r "$INSTDIR\logs"
  RMDir  /r "$INSTDIR\program"
  RMDir  /r "$INSTDIR\agent"
  RMDir  "$INSTDIR"

  Delete "$DESKTOP\NeoOptimize.lnk"
  RMDir  /r "$SMPROGRAMS\NeoOptimize"

  DeleteRegKey HKLM "Software\NeoOptimize"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoOptimize"
  DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "NeoOptimizeAgent"

SectionEnd
