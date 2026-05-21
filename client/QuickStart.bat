@echo off
REM NeoOptimize v1.0 - Quick Start Launcher
REM 
REM VERSION: 1.0
REM EDITION: Standard
REM AUTHOR: NeoOptimize Official
REM 

title NeoOptimize v1.0 - Quick Start

REM Check for administrator privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    echo  Administrator privileges detected
    goto :start
) else (
    echo  Administrator privileges required!
    echo.
    echo Attempting to elevate privileges...
    echo.
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:start
REM Set colors for better UI
color 0A

cls
echo.
echo 
echo                                                                                
echo                 NeoOptimize v1.0 - QUICK START                        
echo                                                                                
echo               Professional Windows System Optimizer - God Mode Edition         
echo                                                                                
echo 
echo.
echo Starting NeoOptimize...
echo.
echo Press any key to exit after optimization completes...
echo.

REM Set PowerShell execution policy for this session
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force"

REM Launch main program in Full Auto mode
powershell -ExecutionPolicy RemoteSigned -File "%~dp0NeoOptimize.ps1" -FullAuto -AssumeYes -NoPause

echo.
echo NeoOptimize has finished.
echo.


exit /b 0
