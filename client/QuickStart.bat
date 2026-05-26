@echo off
setlocal EnableExtensions
title NeoOptimize Safe Care Quick Start

net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo Administrator privileges are required.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

cd /d "%~dp0"
echo.
echo NeoOptimize Safe Care Plan
echo Runs dashboard audit, deep scan, light cleanup, diagnostics, and AI report.
echo High-risk repair or policy changes remain locked behind confirmation.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0NeoOptimize.ps1" -FullAuto
echo.
echo NeoOptimize Safe Care completed.
pause
