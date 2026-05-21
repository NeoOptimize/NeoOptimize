@echo off
REM NeoOptimize v1.0 - Professional Uninstaller
REM 
REM VERSION: 1.0
REM EDITION: Standard
REM AUTHOR: NeoOptimize Official
REM 

title NeoOptimize v1.0 - Professional Uninstaller

REM Check for administrator privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    echo  Administrator privileges detected
) else (
    echo  Administrator privileges required for uninstallation!
    echo Please run as Administrator
    pause
    exit /b 1
)

REM Set colors for better UI
color 0C

cls
echo.
echo 
echo                                                                                
echo                 NeoOptimize v1.0 - PROFESSIONAL UNINSTALLER           
echo                                                                                
echo               Professional Windows System Optimizer - God Mode Edition         
echo                                                                                
echo 
echo.
echo This will completely remove NeoOptimize from your system.
echo.
echo The following will be removed:
echo  Desktop shortcut
echo  Start Menu entry
echo  Program files (optional)
echo.
echo WARNING: This will NOT remove created restore points or log files.
echo.
set /p choice="Are you sure you want to uninstall NeoOptimize? (Y/N): "
if /i not "%choice%"=="Y" (
    echo.
    echo Uninstallation cancelled.
    pause
    exit /b 0
)

cls
echo.
echo 
echo                           UNINSTALLATION IN PROGRESS                         
echo 
echo.

REM Remove desktop shortcut
echo Removing desktop shortcut...
if exist "%USERPROFILE%\Desktop\NeoOptimize.lnk" (
    del "%USERPROFILE%\Desktop\NeoOptimize.lnk"
    echo  Desktop shortcut removed
) else (
    echo  Desktop shortcut not found
)

echo.

REM Remove Start Menu entry
echo Removing Start Menu entry...
if exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs\NeoOptimize" (
    rmdir /s /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\NeoOptimize"
    echo  Start Menu entry removed
) else (
    echo  Start Menu entry not found
)

echo.

REM Ask about removing program files
echo.
set /p remove_files="Remove program files from installation directory? (Y/N): "
if /i "%remove_files%"=="Y" (
    echo.
    echo WARNING: This will delete all NeoOptimize files!
    echo Installation directory: %~dp0
    echo.
    set /p confirm="Are you absolutely sure? (type 'YES' to confirm): "
    if "%confirm%"=="YES" (
        echo Removing program files...
        set "INSTALL_DIR=%~dp0"
        set "INSTALL_DIR=%INSTALL_DIR:~0,-1%"
        cd /d "%~dp0.."
        rmdir /s /q "%INSTALL_DIR%"
        if %errorLevel% == 0 (
            echo  Program files removed
        ) else (
            echo  Failed to remove program files
        )
    ) else (
        echo Program files removal cancelled.
    )
) else (
    echo Program files kept in installation directory.
)

echo.

REM Reset PowerShell execution policy (optional)
echo.
set /p reset_policy="Reset PowerShell execution policy to default? (Y/N): "
if /i "%reset_policy%"=="Y" (
    echo Resetting PowerShell execution policy...
    powershell -Command "Set-ExecutionPolicy -ExecutionPolicy Restricted -Scope CurrentUser -Force" >nul 2>&1
    if %errorLevel% == 0 (
        echo  PowerShell execution policy reset
    ) else (
        echo  Failed to reset PowerShell execution policy
    )
)

echo.

cls
echo.
echo 
echo                            UNINSTALLATION COMPLETE!                         
echo 
echo.
echo NeoOptimize v1.0 has been successfully uninstalled!
echo.
if /i not "%remove_files%"=="Y" (
    echo Note: Program files are still located in the installation directory.
    echo You can safely delete the entire folder if desired.
    echo.
)

echo 
echo Thank you for using NeoOptimize!
echo.
pause

exit /b 0
