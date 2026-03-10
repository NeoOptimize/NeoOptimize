@echo off
setlocal
cd /d "%~dp0"
start "NeoOptimize Service" /min "%~dp0Service\NeoOptimize.Service.exe"
timeout /t 2 >nul
start "NeoOptimize App" "%~dp0App\NeoOptimize.App.exe"
endlocal
