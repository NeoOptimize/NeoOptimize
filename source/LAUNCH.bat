@echo off
:: ╔══════════════════════════════════════════════════════════════════╗
:: ║   NeoOptimize v1.0 — Windows Optimizer & Agent                   ║
:: ║   Professional Tool for Computer Technicians                     ║
:: ║   Email   : neooptimizeofficial@gmail.com                       ║
:: ║   Donasi  : buymeacoffee.com/nol.eight | saweria.co/dtechtive   ║
:: ╚══════════════════════════════════════════════════════════════════╝
title NeoOptimize v1.0 — Windows Optimizer & Agent
color 0B

:: ── Check Administrator ────────────────────────────────────────────────────────
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo.
    echo   [!] Membutuhkan hak Administrator.
    echo   [*] Meminta elevasi...
    echo.
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:: ── Check PowerShell version ───────────────────────────────────────────────────
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

:: ── Check Script Exists ────────────────────────────────────────────────────────
if not exist "%~dp0NeoOptimize.ps1" (
    echo.
    echo   [!] NeoOptimize.ps1 tidak ditemukan!
    echo   [*] Pastikan semua file ada dalam 1 folder.
    echo.
    pause
    exit /b
)

:: ── Set console size for best experience ──────────────────────────────────────
mode con: cols=90 lines=45

:: ── Launch ────────────────────────────────────────────────────────────────────
echo   [*] Meluncurkan NeoOptimize...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0NeoOptimize.ps1"

if %errorLevel% NEQ 0 (
    echo.
    echo   [!] Error saat menjalankan NeoOptimize.
    echo   [*] Pastikan Anda menjalankan sebagai Administrator.
    echo   [*] Coba: klik kanan LAUNCH.bat → Run as administrator
    echo.
    pause
)
