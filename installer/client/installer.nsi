; ═══════════════════════════════════════════════════════════════════
; NeoOptimize Setup — NSIS Installer Script
; Public lightweight package.
; ═══════════════════════════════════════════════════════════════════

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "nsDialogs.nsh"

; ─── Metadata ─────────────────────────────────────────────────────
Name              "NeoOptimize"
OutFile           "NeoOptimize.exe"
Icon              "logo.ico"
UninstallIcon     "logo.ico"
InstallDir        "$PROGRAMFILES64\NeoOptimize"
InstallDirRegKey  HKLM "Software\NeoOptimize" "InstallDir"
RequestExecutionLevel admin
Unicode True

; ─── Version ──────────────────────────────────────────────────────
VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName"     "NeoOptimize"
VIAddVersionKey "CompanyName"     "Zenthralix Technologies"
VIAddVersionKey "LegalCopyright"  "© 2025 Zenthralix Technologies"
VIAddVersionKey "FileDescription" "NeoOptimize System Optimizer"
VIAddVersionKey "FileVersion"     "1.0"

; ─── MUI Configuration ────────────────────────────────────────────
!define MUI_ABORTWARNING

!define MUI_WELCOMEPAGE_TITLE    "Welcome to NeoOptimize Setup"
!define MUI_WELCOMEPAGE_TEXT     "This will install NeoOptimize System Optimizer on your computer.$\n$\nNeoOptimize provides a lightweight AI-powered Windows maintenance console with safety checks, diagnostics, cleanup, repair, and update workflows."

!define MUI_FINISHPAGE_RUN           "$INSTDIR\program\NeoOptimize.exe"
!define MUI_FINISHPAGE_RUN_TEXT      "Launch NeoOptimize after install"
!define MUI_FINISHPAGE_SHOWREADME    "$INSTDIR\program\README_ZENTHRALIX_LAB.txt"
!define MUI_FINISHPAGE_SHOWREADME_TEXT "Open zenthralix-lab Show Me"
!define MUI_FINISHPAGE_TEXT          "NeoOptimize has been installed successfully.$\n$\nThe optimizer is ready. Optional endpoint sync can be configured separately by an authorized administrator."

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
Var EnrollmentToken
Var Dialog

Function ServerConfigPage
  ; Public mode does not show or configure backend endpoints.
  ; Enterprise/lab builds can still pass /SERVER=<url> to seed local config.
  ${GetParameters} $R0
  ${GetOptions} $R0 "/SERVER=" $R1
  ${If} $R1 != ""
    StrCpy $ServerUrl $R1
  ${EndIf}
  ${GetOptions} $R0 "/ENROLLMENT_TOKEN=" $R2
  ${If} $R2 != ""
    StrCpy $EnrollmentToken $R2
  ${EndIf}
  Abort  ; Skip this page
  Abort

  nsDialogs::Create 1018
  Pop $Dialog
  ${If} $Dialog == error
    Abort
  ${EndIf}

  ${NSD_CreateLabel} 0 0 100% 20u "Endpoint Sync Configuration"
  Pop $0
  SetCtlColors $0 0x00c6ff 0x060b14

  ${NSD_CreateLabel} 0 30u 100% 12u "Server URL (provided by your IT administrator):"
  Pop $0

  ${NSD_CreateText} 0 46u 100% 14u "http://192.168.122.1:3000"
  Pop $ServerUrlField

  ${NSD_CreateLabel} 0 66u 100% 24u "Enter an authorized endpoint sync address only for enterprise/lab enrollment."
  Pop $0

  nsDialogs::Show
FunctionEnd

Function ServerConfigPageLeave
  ${NSD_GetText} $ServerUrlField $ServerUrl
  ${If} $ServerUrl == ""
    StrCpy $ServerUrl "http://192.168.122.1:3000"
  ${EndIf}
FunctionEnd

Function StopExistingUi
  DetailPrint "Closing existing NeoOptimize UI sessions..."
  ; The public installer is also named NeoOptimize.exe. Never kill by image
  ; name only, or the installer terminates itself before copying payload files.
  nsExec::ExecToLog '"$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand RwBlAHQALQBDAGkAbQBJAG4AcwB0AGEAbgBjAGUAIABXAGkAbgAzADIAXwBQAHIAbwBjAGUAcwBzACAAfAAgAFcAaABlAHIAZQAtAE8AYgBqAGUAYwB0ACAAewAgACgAJABfAC4ATgBhAG0AZQAgAC0AZQBxACAAJwBwAG8AdwBlAHIAcwBoAGUAbABsAC4AZQB4AGUAJwAgAC0AbwByACAAJABfAC4ATgBhAG0AZQAgAC0AZQBxACAAJwBwAHcAcwBoAC4AZQB4AGUAJwApACAALQBhAG4AZAAgACQAXwAuAEMAbwBtAG0AYQBuAGQATABpAG4AZQAgAC0AbQBhAHQAYwBoACAAJwBOAGUAbwBPAHAAdABpAG0AaQB6AGUAJwAgAH0AIAB8ACAARgBvAHIARQBhAGMAaAAtAE8AYgBqAGUAYwB0ACAAewAgAFMAdABvAHAALQBQAHIAbwBjAGUAcwBzACAALQBJAGQAIAAkAF8ALgBQAHIAbwBjAGUAcwBzAEkAZAAgAC0ARgBvAHIAYwBlACAALQBFAHIAcgBvAHIAQQBjAHQAaQBvAG4AIABTAGkAbABlAG4AdABsAHkAQwBvAG4AdABpAG4AdQBlACAAfQAKAA=='
  Pop $0
  nsExec::ExecToLog `"$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "$$root = '$INSTDIR\program\'; Get-CimInstance Win32_Process | Where-Object { $$_.Name -eq 'NeoOptimize.exe' -and $$_.ExecutablePath -like ($$root + '*') } | ForEach-Object { Stop-Process -Id $$_.ProcessId -Force -ErrorAction SilentlyContinue }"`
  Pop $0
  Sleep 1000
FunctionEnd

Function StopExistingAgent
  DetailPrint "Stopping existing NeoOptimize endpoint sync agent..."
  nsExec::ExecToLog '"$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand JABuAGEAbQBlAHMAIAA9ACAAQAAoACIATgBlAG8ATwBwAHQAaQBtAGkAegBlACAAUgBNAE0AIABBAGcAZQBuAHQAIgAsACIATgBlAG8ATwBwAHQAaQBtAGkAegBlAEEAZwBlAG4AdAAiACkAOwAgAGYAbwByAGUAYQBjAGgAIAAoACQAbgBhAG0AZQAgAGkAbgAgACQAbgBhAG0AZQBzACkAIAB7ACAAJABzAHYAYwAgAD0AIABHAGUAdAAtAFMAZQByAHYAaQBjAGUAIAAtAE4AYQBtAGUAIAAkAG4AYQBtAGUAIAAtAEUAcgByAG8AcgBBAGMAdABpAG8AbgAgAFMAaQBsAGUAbgB0AGwAeQBDAG8AbgB0AGkAbgB1AGUAOwAgAGkAZgAgACgAJABzAHYAYwApACAAewAgAHQAcgB5ACAAewAgAFMAdABvAHAALQBTAGUAcgB2AGkAYwBlACAALQBOAGEAbQBlACAAJABuAGEAbQBlACAALQBGAG8AcgBjAGUAIAAtAEUAcgByAG8AcgBBAGMAdABpAG8AbgAgAFMAaQBsAGUAbgB0AGwAeQBDAG8AbgB0AGkAbgB1AGUAIAB9ACAAYwBhAHQAYwBoACAAewB9ACAAfQAgAH0AOwAgAFMAdABhAHIAdAAtAFMAbABlAGUAcAAgAC0AUwBlAGMAbwBuAGQAcwAgADIAOwAgAEcAZQB0AC0AQwBpAG0ASQBuAHMAdABhAG4AYwBlACAAVwBpAG4AMwAyAF8AUAByAG8AYwBlAHMAcwAgAHwAIABXAGgAZQByAGUALQBPAGIAagBlAGMAdAAgAHsAIAAkAF8ALgBFAHgAZQBjAHUAdABhAGIAbABlAFAAYQB0AGgAIAAtAG0AYQB0AGMAaAAgACIATgBlAG8ATwBwAHQAaQBtAGkAegBlAC4AKgBBAGcAZQBuAHQALgAqAFwALgBlAHgAZQAiACAAfQAgAHwAIABGAG8AcgBFAGEAYwBoAC0ATwBiAGoAZQBjAHQAIAB7ACAAUwB0AG8AcAAtAFAAcgBvAGMAZQBzAHMAIAAtAEkAZAAgACQAXwAuAFAAcgBvAGMAZQBzAEkAZAAgAC0ARgBvAHIAYwBlACAALQBFAHIAcgBvAHIAQQBjAHQAaQBvAG4AIABTAGkAbABlAG4AdABsAHkAQwBvAG4AdABpAG4AdQBlAIAB9AA=='
  Pop $0
  Sleep 1000
FunctionEnd

; ─── Install ──────────────────────────────────────────────────────
Section "NeoOptimize Core" SEC01
  SectionIn RO  ; Required

  DetailPrint "Preparing NeoOptimize public installation..."
  Call StopExistingUi
  Call StopExistingAgent

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
  RMDir /r "$INSTDIR\program\knowledge"
  RMDir /r "$INSTDIR\program\skills"
  RMDir /r "$INSTDIR\program\mcp"
  RMDir /r "$INSTDIR\program\tools"
  Delete "$INSTDIR\program\NeoOptimize.exe"
  Delete "$INSTDIR\program\WebView2Loader.dll"
  Delete "$INSTDIR\program\NeoOptimize.Launcher.vbs"

  ; Core files
  File "bin\NeoOptimize.exe"
  File "bin\WebView2Loader.dll"
  File "LAUNCH.bat"
  File "QuickStart.bat"
  File "signing.pub.pem"
  File "README_ZENTHRALIX_LAB.txt"
  File "NeoOptimize.Launcher.ps1"
  File "NeoOptimize.UI.ps1"
  File "NeoOptimize.ps1"
  File "NeoOptimize.UpdateManager.ps1"
  File "NeoOptimize.AIAgent.ps1"
  File "NeoOptimize.AgenticRunner.ps1"
  File "NeoOptimize.Tray.ps1"
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

  SetOutPath "$INSTDIR\program\knowledge"
  File /r "knowledge\*.*"

  SetOutPath "$INSTDIR\program\skills"
  File /r "skills\*.*"

  SetOutPath "$INSTDIR\program\mcp"
  File /r "mcp\*.*"

  SetOutPath "$INSTDIR\program\tools"
  File /r "tools\*.*"

  SetOutPath "$INSTDIR\program"
  CreateDirectory "$INSTDIR\program\logs"
  CreateDirectory "$INSTDIR\program\reports"

  ; Uninstaller
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; Registry entries
  WriteRegStr HKLM "Software\NeoOptimize" "InstallDir" "$INSTDIR"
  ${If} $ServerUrl != ""
    WriteRegStr HKLM "Software\NeoOptimize" "ServerUrl"  "$ServerUrl"
  ${EndIf}
  WriteRegStr HKLM "Software\NeoOptimize" "Version"    "1.0"

  ; Add to Programs & Features
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoOptimize" \
    "DisplayName"     "NeoOptimize"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoOptimize" \
    "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoOptimize" \
    "DisplayVersion"  "1.0"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoOptimize" \
    "Publisher"       "Zenthralix Technologies"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoOptimize" \
    "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoOptimize" \
    "NoRepair" 1

  ; Desktop shortcut for NeoOptimize. Uses the native lightweight UI. The
  ; PowerShell launcher remains as fallback only.
  CreateShortcut "$DESKTOP\NeoOptimize.lnk" "$INSTDIR\program\NeoOptimize.exe" "" "$INSTDIR\program\assets\NeoOptimize.ico"

  ; Start menu
  CreateDirectory "$SMPROGRAMS\NeoOptimize"
  CreateShortcut "$SMPROGRAMS\NeoOptimize\NeoOptimize.lnk" "$INSTDIR\program\NeoOptimize.exe" "" "$INSTDIR\program\assets\NeoOptimize.ico"
  CreateShortcut "$SMPROGRAMS\NeoOptimize\Mini Tray.lnk" "$INSTDIR\program\NeoOptimize.exe" "--tray" "$INSTDIR\program\assets\NeoOptimize.ico"
  CreateShortcut "$SMPROGRAMS\NeoOptimize\Update Manager.lnk" "$INSTDIR\program\NeoOptimize.exe" "--update" "$INSTDIR\program\assets\NeoOptimize.ico"
  CreateShortcut "$SMPROGRAMS\NeoOptimize\Show Me.lnk" "$WINDIR\System32\notepad.exe" "$INSTDIR\program\README_ZENTHRALIX_LAB.txt"
  CreateShortcut "$SMPROGRAMS\NeoOptimize\Uninstall.lnk"   "$INSTDIR\Uninstall.exe"

  ; Lightweight tray monitor at user login. It stays user-visible and opens
  ; local NEO chat, voice command, monitor, and update tools.
  CreateShortcut "$SMSTARTUP\NeoOptimize Mini Tray.lnk" "$INSTDIR\program\NeoOptimize.exe" "--tray" "$INSTDIR\program\assets\NeoOptimize.ico"

  ; Local AI bootstrap: configure Ollama model storage, import bundled NEO
  ; models when present, and download/install official Ollama when absent.
  ; The helper runs its child processes with CreateNoWindow, so no CMD window
  ; appears while neo-light:latest, neo:latest, and neo-latest:latest are prepared.
  nsExec::ExecToLog '"$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$INSTDIR\program\tools\Install-NeoOptimizeOllama.ps1" -Ensure -Download -Install -ImportBundledModels -PullRequiredModels -Silent -Force -Background'
  Pop $0

  ; Endpoint sync worker: installs the hidden local scheduled task that links
  ; NeoOptimize to a reachable authorized RMM server when config/token exist.
  nsExec::ExecToLog '"$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$INSTDIR\program\NeoOptimizeAgent.ps1" -Mode Install -Quiet -NoOpen -AssumeYes'
  Pop $0

SectionEnd

; ─── Enterprise Endpoint Sync Add-on Placeholder ──────────────────
; The public installer stays lightweight and does not bundle or auto-start
; the enterprise endpoint sync service. Authorized enterprise enrollment can
; install that connector separately.
Section /o "Endpoint Sync Agent (Enterprise Add-on)" SEC02
  DetailPrint "Endpoint sync agent is not included in the public lightweight package."
SectionEnd

; ─── Uninstall ────────────────────────────────────────────────────
Section "Uninstall"

  IfFileExists "$PROGRAMFILES\NeoOptimize\Agent\NeoOptimize_Uninstaller.ps1" 0 +2
  nsExec::ExecToLog '"$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$PROGRAMFILES\NeoOptimize\Agent\NeoOptimize_Uninstaller.ps1" -InstallDir "$PROGRAMFILES\NeoOptimize\Agent"'
  Pop $0

  nsExec::ExecToLog '"$WINDIR\System32\taskkill.exe" /F /T /IM "NeoOptimize.exe"'
  Pop $0
  nsExec::ExecToLog '"$WINDIR\System32\taskkill.exe" /F /T /IM "NeoOptimize.Agent.exe"'
  Pop $0
  nsExec::ExecToLog '"$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand VQBuAHIAZQBnAGkAcwB0AGUAcgAtAFMAYwBoAGUAZAB1AGQAZQBkAFQAYQBzAGsAIAAtAFQAYQBzAGsATgBhAG0AZQAgACcATgBlAG8ATwBwAHQAaQBtAGkAegBlAC0ARQBuAGQAcABvAGkAbgB0AC0AUwB5AG4AYwAnACAALQBDAG8AbgBmAGkAcgBtADoAJABmAGEAbABzAGUAIAAtAEUAcgByAG8AcgBBAGMAdABpAG8AbgAgAFMAaQBsAGUAbgB0AGwAeQBDAG8AbgB0AGkAbgB1AGUACgBVAG4AcgBlAGcAaQBzAHQAZQByAC0AUwBjAGgAZQBkAHUAbABlAGQAVABhAHMAawAgAC0AVABhAHMAawBOAGEAbQBlACAAJwBOAGUAbwBPAHAAdABpAG0AaQB6AGUALQBBAGcAZQBuAHQALQBBAHUAZABpAHQAJwAgAC0AQwBvAG4AZgBpAHIAbQA6ACQAZgBhAGwAcwBlACAALQBFAHIAcgBvAHIAQQBjAHQAaQBvAG4AIABTAGkAbABlAG4AdABsAHkAQwBvAG4AdABpAG4AdQBlAAoA"'
  Pop $0
  Sleep 1000

  Delete "$INSTDIR\NeoOptimize.exe"
  Delete "$INSTDIR\WebView2Loader.dll"
  Delete "$INSTDIR\NeoOptimize.Agent.exe"
  Delete "$INSTDIR\agent\NeoOptimize.Agent.exe"
  Delete "$INSTDIR\appsettings.json"
  Delete "$INSTDIR\README_ZENTHRALIX_LAB.txt"
  Delete "$INSTDIR\NeoOptimize.UI.ps1"
  Delete "$INSTDIR\NeoOptimize.Launcher.ps1"
  Delete "$INSTDIR\NeoOptimize.Launcher.vbs"
  Delete "$INSTDIR\program\NeoOptimize.Launcher.ps1"
  Delete "$INSTDIR\program\NeoOptimize.Launcher.vbs"
  Delete "$INSTDIR\program\WebView2Loader.dll"
  Delete "$INSTDIR\NeoOptimize.ps1"
  Delete "$INSTDIR\NeoOptimize.AIAgent.ps1"
  Delete "$INSTDIR\NeoOptimize.AgenticRunner.ps1"
  Delete "$INSTDIR\program\NeoOptimize.AgenticRunner.ps1"
  Delete "$INSTDIR\NeoOptimize.Tray.ps1"
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
  RMDir  /r "$INSTDIR\skills"
  RMDir  /r "$INSTDIR\mcp"
  RMDir  /r "$INSTDIR\tools"
  RMDir  /r "$INSTDIR\reports"
  RMDir  /r "$INSTDIR\logs"
  RMDir  /r "$INSTDIR\program"
  RMDir  /r "$INSTDIR\agent"
  RMDir  /r "$LOCALAPPDATA\NeoOptimize"
  RMDir  /r "$APPDATA\NeoOptimize"
  RMDir  "$INSTDIR"

  Delete "$DESKTOP\NeoOptimize.lnk"
  Delete "$SMSTARTUP\NeoOptimize Mini Tray.lnk"
  RMDir  /r "$SMPROGRAMS\NeoOptimize"

  DeleteRegKey HKLM "Software\NeoOptimize"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoOptimize"
  DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "NeoOptimizeAgent"

SectionEnd
