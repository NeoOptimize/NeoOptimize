@echo off
setlocal EnableExtensions

set "LOG=C:\NeoOptimize-VM-Test.log"
set "SRC=%~dp0"

echo NeoOptimize VM test started %DATE% %TIME% > "%LOG%"
echo Source: %SRC% >> "%LOG%"

echo Copying final installer to C:\NeoOptimize.exe... >> "%LOG%"
copy /Y "%SRC%NeoOptimize.exe" "C:\NeoOptimize.exe" >> "%LOG%" 2>&1
echo COPY_EXIT=%ERRORLEVEL% >> "%LOG%"

echo Running NeoOptimize client static self-test from ISO... >> "%LOG%"
powershell -NoProfile -ExecutionPolicy RemoteSigned -File "%SRC%client\tools\Invoke-NeoOptimizeSelfTest.ps1" >> "%LOG%" 2>&1
set "SELFTEST_EXIT=%ERRORLEVEL%"
echo SELFTEST_EXIT=%SELFTEST_EXIT% >> "%LOG%"

echo. >> "%LOG%"
echo Installer path: C:\NeoOptimize.exe >> "%LOG%"
echo NeoOptimize VM test finished %DATE% %TIME% >> "%LOG%"

type "%LOG%"
exit /b %SELFTEST_EXIT%
