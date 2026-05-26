@echo off
setlocal EnableExtensions
title NeoOptimize Local Shortcut Installer

net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo Administrator privileges are required.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

cd /d "%~dp0"
echo.
echo NeoOptimize Local Shortcut Installer
echo This helper only creates shortcuts for a source checkout.
echo Public distribution should use the signed NSIS installer from GitHub Releases.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=(Resolve-Path '.').Path;" ^
  "$target=Join-Path $root 'LAUNCH.bat';" ^
  "$icon=Join-Path $root 'assets\NeoOptimize.ico';" ^
  "$shell=New-Object -ComObject WScript.Shell;" ^
  "$desktop=[Environment]::GetFolderPath('Desktop');" ^
  "$lnk=$shell.CreateShortcut((Join-Path $desktop 'NeoOptimize.lnk'));" ^
  "$lnk.TargetPath=$target; $lnk.WorkingDirectory=$root; if(Test-Path $icon){$lnk.IconLocation=$icon}; $lnk.Description='NeoOptimize Endpoint Operations Console'; $lnk.Save();" ^
  "$start=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\NeoOptimize';" ^
  "New-Item -Path $start -ItemType Directory -Force | Out-Null;" ^
  "$lnk2=$shell.CreateShortcut((Join-Path $start 'NeoOptimize.lnk'));" ^
  "$lnk2.TargetPath=$target; $lnk2.WorkingDirectory=$root; if(Test-Path $icon){$lnk2.IconLocation=$icon}; $lnk2.Description='NeoOptimize Endpoint Operations Console'; $lnk2.Save();"

echo.
echo Shortcuts created. Launch NeoOptimize from Desktop or Start Menu.
pause
