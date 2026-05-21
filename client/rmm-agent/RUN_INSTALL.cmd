@echo off
setlocal
net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
  echo Requesting Administrator rights...
  powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
cd /d "%~dp0"
echo NeoOptimize RMM Agent install test
echo Source: %~dp0
echo.
taskkill /F /IM NeoOptimize.Agent.exe >nul 2>&1
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0NeoOptimize.Agent.Install.ps1"
set RC=%ERRORLEVEL%
echo.
echo Installer exit code: %RC%
echo.
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -Command "Get-Service 'NeoOptimize RMM Agent' -ErrorAction SilentlyContinue | Format-List Name,Status,StartType,ServiceType"
echo.
echo Writing logs to C:\NeoOptimize-Agent-Install-Test.txt
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -Command "'Install exit code: %RC%' | Set-Content C:\NeoOptimize-Agent-Install-Test.txt; Get-Service 'NeoOptimize RMM Agent' -ErrorAction SilentlyContinue | Format-List Name,Status,StartType,ServiceType | Out-File -Append C:\NeoOptimize-Agent-Install-Test.txt"
echo.
pause
exit /b %RC%
