; ==========================================
; NeoOptimize Next-Gen Advanced Installer
; Neat & Sophisticated Modern UI 2 Setup
; ==========================================

!include "MUI2.nsh"
!include "FileFunc.nsh"

; Define Product Information
!define PRODUCT_NAME "NeoOptimize"
!define PRODUCT_VERSION "1.0"
!define PRODUCT_PUBLISHER "Zenthralix-lab"
!define PRODUCT_WEB_SITE "https://buymeacoffee.com/nol.eight"
!define PRODUCT_DIR_REGKEY "Software\Microsoft\Windows\CurrentVersion\App Paths\LAUNCH.bat"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"

; Compression & Optimization Settings
SetCompressor /SOLID lzma
Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "..\release\NeoOptimize.exe"
InstallDir "$PROGRAMFILES\NeoOptimize"
InstallDirRegKey HKLM "${PRODUCT_DIR_REGKEY}" ""
RequestExecutionLevel admin
ShowInstDetails show
ShowUnInstDetails show

; Graphic Customizations
!define MUI_ICON "assets\NeoOptimize.ico"
!define MUI_UNICON "assets\NeoOptimize.ico"

; Modern UI Pages Configuration
!define MUI_ABORTWARNING

; Welcome Page Settings
!insertmacro MUI_PAGE_WELCOME

; License / Readme Page Settings
!define MUI_LICENSEPAGE_BUTTON "Agree & Continue"
!insertmacro MUI_PAGE_LICENSE "INSTALL.md"

; Directory Page Settings
!insertmacro MUI_PAGE_DIRECTORY

; Installation Page Settings
!insertmacro MUI_PAGE_INSTFILES

; Finish Page Settings
!define MUI_FINISHPAGE_RUN "$INSTDIR\program\NeoOptimize.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Luncurkan NeoOptimize System Repair Console"
!insertmacro MUI_PAGE_FINISH

; Uninstaller Pages Configuration
!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

; Languages Setup
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Indonesian"

; ==========================================
; Installation Sections
; ==========================================

Section "MainSection" SEC01
  CreateDirectory "$INSTDIR\program"
  SetOutPath "$INSTDIR\program"
  SetOverwrite ifnewer
  
  ; Menyalin file penting. RMM agent ikut dipaketkan agar NeoOptimize bisa terhubung ke RMM bila server tersedia.
  ; models/ dan datasets/ sengaja ikut dipaketkan karena NeoCore AI lokal membutuhkannya.
  File /r /x "*.iso" /x "*.zip" /x "*.pyc" /x ".git" /x "__pycache__" /x "backup" /x "hf_space" /x "nsDiag*" /x "neo_installer.nsi" "*.*"

  ; Membuat Pintasan di Desktop
  SetFileAttributes "$INSTDIR\program" HIDDEN|SYSTEM

  CreateShortCut "$DESKTOP\NeoOptimize.lnk" "$INSTDIR\program\NeoOptimize.exe" "" "$INSTDIR\program\assets\NeoOptimize.ico" 0
  
  ; Membuat Pintasan di Start Menu
  CreateDirectory "$SMPROGRAMS\NeoOptimize"
  CreateShortCut "$SMPROGRAMS\NeoOptimize\NeoOptimize.lnk" "$INSTDIR\program\NeoOptimize.exe" "" "$INSTDIR\program\assets\NeoOptimize.ico" 0
  CreateShortCut "$SMPROGRAMS\NeoOptimize\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
  
  ; Mengonfigurasi Execution Policy PowerShell secara global untuk sistem
  ExecWait 'powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force"'
  ExecWait 'powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force"'

  ; Hubungkan ke RMM bila server terdeteksi. Script akan skip bersih jika server belum hidup.
  ExecWait 'powershell -NoProfile -ExecutionPolicy RemoteSigned -File "$INSTDIR\program\NeoOptimize.RMMBootstrap.ps1"'
SectionEnd

Section -Post
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  
  ; Register App Path
  WriteRegStr HKLM "${PRODUCT_DIR_REGKEY}" "" "$INSTDIR\program\LAUNCH.bat"
  
  ; Register Windows Uninstall Entry (Control Panel)
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayName" "NeoOptimize Systems Repair Console"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "UninstallString" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayIcon" "$INSTDIR\program\assets\NeoOptimize.ico"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
  WriteRegDWORD HKLM "${PRODUCT_UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${PRODUCT_UNINST_KEY}" "NoRepair" 1
SectionEnd

; ==========================================
; Uninstallation Section
; ==========================================

Section Uninstall
  ; Menghapus Pintasan
  Delete "$DESKTOP\NeoOptimize.lnk"
  RMDir /r "$SMPROGRAMS\NeoOptimize"
  
  ; Menghapus Semua File dan Folder Instalasi
  RMDir /r "$INSTDIR"

  ; Menghapus Entri Registry
  DeleteRegKey HKLM "${PRODUCT_UNINST_KEY}"
  DeleteRegKey HKLM "${PRODUCT_DIR_REGKEY}"
  
  SetAutoClose true
SectionEnd
