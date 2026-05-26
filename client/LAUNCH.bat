@echo off
:: 
::    NeoOptimize v1.0  Windows Optimizer and Agent                   
::    Professional Tool for Computer Technicians                     
:: 
title NeoOptimize Control Center
color 0B

:: Prefer the native Rust/Tauri UI. PowerShell is only a hidden worker fallback.
if exist "%~dp0NeoOptimize.exe" (
    start "" "%~dp0NeoOptimize.exe" %*
    exit /b 0
)

if exist "%~dp0NeoOptimize.Launcher.ps1" (
    start "" "%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0NeoOptimize.Launcher.ps1"
    exit /b 0
)

::  Check Administrator 
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo.
    echo   [!] Membutuhkan hak Administrator.
    echo   [*] Meminta elevasi...
    echo.
    powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe' -ArgumentList '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"%~dp0NeoOptimize.Launcher.ps1\"' -Verb RunAs -WindowStyle Hidden"
    exit /b
)

::  Check PowerShell version 
echo.
echo   [*] Memeriksa PowerShell...
powershell -Command "if ($PSVersionTable.PSVersion.Major -lt 5) { Write-Host '  [!] PowerShell 5.1+ diperlukan.' -ForegroundColor Red; exit 1 }"
if %errorLevel% NEQ 0 (
    echo.
    echo   [!] PowerShell versi lama terdeteksi.
    echo   [*] Install Windows Management Framework 5.1 dari microsoft.com
    echo.
    pause
    exit /b
)

::  Check Script Exists 
if not exist "%~dp0NeoOptimize.ps1" (
    echo.
    echo   [!] NeoOptimize.ps1 tidak ditemukan!
    echo   [*] Pastikan semua file ada dalam 1 folder.
    echo.
    pause
    exit /b
)

::  Set console size for best experience 
mode con: cols=90 lines=45

::  Launch modern UI when available
if exist "%~dp0NeoOptimize.UI.ps1" (
    echo   [*] Meluncurkan NeoOptimize Modern UI...
    echo.
    powershell -Sta -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0NeoOptimize.UI.ps1"
    goto :HANDLE_EXIT
)

::  Console fallback
echo   [*] Meluncurkan NeoOptimize Console...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0NeoOptimize.ps1"

:HANDLE_EXIT
if %errorLevel% NEQ 0 (
    echo.
    echo   [!] Error saat menjalankan NeoOptimize.
    echo   [*] Pastikan Anda menjalankan sebagai Administrator.
    echo   [*] Coba: klik kanan LAUNCH.bat  Run as administrator
    echo.
)
