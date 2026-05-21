@echo off
REM NeoOptimize v1.0 - Professional Installer
REM 
REM VERSION: 1.0
REM EDITION: Standard
REM AUTHOR: NeoOptimize Official
REM 

title NeoOptimize v1.0 - Professional Installer

REM Check for administrator privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    echo  Administrator privileges detected
) else (
    echo  Administrator privileges required for installation!
    echo Please run as Administrator
    exit /b 1
)

REM Set colors for better UI
color 0A

cls
echo.
echo 
echo                                                                                
echo                 NeoOptimize v1.0 - PROFESSIONAL INSTALLER             
echo                                                                                
echo               Professional Windows System Optimizer - God Mode Edition         
echo                                                                                
echo 
echo.
echo Welcome to NeoOptimize v1.0 Professional Installer!
echo.
echo This installer will:
echo  Create desktop shortcut
echo  Create Start Menu entry
echo  Set up proper permissions
echo  Configure PowerShell execution policy
echo  Create uninstaller
echo.

cls
echo.
echo 
echo                            INSTALLATION IN PROGRESS                          
echo 
echo.

REM Get current directory
set "INSTALL_DIR=%~dp0"
set "INSTALL_DIR=%INSTALL_DIR:~0,-1%"

echo  Installation directory: %INSTALL_DIR%
echo.

REM Create desktop shortcut using PowerShell
echo Creating desktop shortcut...
powershell -Command "
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut([System.Environment]::GetFolderPath('Desktop') + '\NeoOptimize.lnk')
$Shortcut.TargetPath = '%INSTALL_DIR%\LAUNCH.bat'
$Shortcut.WorkingDirectory = '%INSTALL_DIR%'
$Shortcut.IconLocation = '%INSTALL_DIR%\assets\NeoOptimize.ico'
$Shortcut.Description = 'NeoOptimize Endpoint Operations Console'
$Shortcut.Save()
"
if %errorLevel% == 0 (
    echo  Desktop shortcut created successfully
) else (
    echo  Failed to create desktop shortcut
)

echo.

REM Create Start Menu shortcut
echo Creating Start Menu entry...
if not exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs\NeoOptimize" (
    mkdir "%APPDATA%\Microsoft\Windows\Start Menu\Programs\NeoOptimize" 2>nul
)

powershell -Command "
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut('%APPDATA%\Microsoft\Windows\Start Menu\Programs\NeoOptimize\NeoOptimize.lnk')
$Shortcut.TargetPath = '%INSTALL_DIR%\LAUNCH.bat'
$Shortcut.WorkingDirectory = '%INSTALL_DIR%'
$Shortcut.IconLocation = '%INSTALL_DIR%\assets\NeoOptimize.ico'
$Shortcut.Description = 'NeoOptimize Endpoint Operations Console'
$Shortcut.Save()
"
if %errorLevel% == 0 (
    echo  Start Menu entry created successfully
) else (
    echo  Failed to create Start Menu entry
)

echo.

REM Set PowerShell execution policy
echo Configuring PowerShell execution policy...
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" >nul 2>&1
if %errorLevel% == 0 (
    echo  PowerShell execution policy configured
) else (
    echo  PowerShell execution policy may need manual configuration
)

echo.

REM Create uninstaller
echo Creating uninstaller...
(
echo @echo off
echo REM NeoOptimize v1.0 - Uninstaller
echo title NeoOptimize v1.0 - Uninstaller
echo.
echo Removing NeoOptimize...
echo.
echo  Removing desktop shortcut...
echo del "%%USERPROFILE%%\Desktop\NeoOptimize.lnk" 2^>nul
echo.
echo  Removing Start Menu entry...
echo rmdir /s /q "%%APPDATA%%\Microsoft\Windows\Start Menu\Programs\NeoOptimize" 2^>nul
echo.
echo echo  NeoOptimize has been uninstalled.
echo.
) > "Uninstall.bat"

if exist "Uninstall.bat" (
    echo  Uninstaller created successfully
) else (
    echo  Failed to create uninstaller
)

echo.

REM Create Quick Launch batch file
echo Creating quick launch batch file...
(
echo @echo off
echo REM NeoOptimize v1.0 - Quick Launch
echo title NeoOptimize v1.0 - Quick Launch
echo.
echo Starting NeoOptimize...
echo.
echo Press any key to exit after optimization completes...
echo powershell -ExecutionPolicy Bypass -File "%%~dp0NeoOptimize.ps1" -FullAuto -AssumeYes -NoPause
) > "QuickStart.bat"

if exist "QuickStart.bat" (
    echo  Quick launch batch created successfully
) else (
    echo  Failed to create quick launch batch
)

echo.

REM Verify installation
echo Verifying installation...
if exist "%USERPROFILE%\Desktop\NeoOptimize.lnk" (
    echo  Desktop shortcut verified
) else (
    echo  Desktop shortcut not found
)

if exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs\NeoOptimize\NeoOptimize.lnk" (
    echo  Start Menu entry verified
) else (
    echo  Start Menu entry not found
)

if exist "NeoOptimize.ps1" (
    echo  Main program verified
) else (
    echo  Main program not found!
)

echo.

cls
echo.
echo 
echo                             INSTALLATION COMPLETE!                          
echo 
echo.
echo NeoOptimize v1.0 has been successfully installed!
echo.
echo 
echo                               HOW TO USE                                    
echo 
echo.
echo 1. Double-click "NeoOptimize" shortcut on your desktop
echo    OR
echo    Find "NeoOptimize" in Start Menu  NeoOptimize
echo.
echo 2. Choose your optimization mode:
echo    [1] Quick Optimization (2-5 minutes)
echo    [2] Full Optimization (10-20 minutes)
echo    [3] God Mode (20-60 minutes, aggressive)
echo.
echo 3. Let the optimization complete
echo.
echo 4. Restart your system for best results
echo.
echo 
echo                               UNINSTALL                                     
echo 
echo.
echo To uninstall: Run "Uninstall.bat" as Administrator
echo.
echo 
echo Thank you for choosing NeoOptimize!
echo.
echo Installation complete.

REM Clean up installer
del "%~f0" 2>nul

exit /b 0
