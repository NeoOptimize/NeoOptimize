@echo off
setlocal EnableExtensions
title NeoOptimize Local Shortcut Uninstaller

echo.
echo NeoOptimize Local Shortcut Uninstaller
echo This helper removes shortcuts created from a source checkout.
echo Installed public releases should be removed from Windows Apps or Programs and Features.
echo.
choice /C YN /N /M "Remove local shortcuts? [Y/N] "
if errorlevel 2 exit /b 0

del "%USERPROFILE%\Desktop\NeoOptimize.lnk" 2>nul
rmdir /s /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\NeoOptimize" 2>nul

echo.
echo Local shortcuts removed.
pause
