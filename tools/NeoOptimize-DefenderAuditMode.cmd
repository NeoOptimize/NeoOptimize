@echo off
setlocal EnableExtensions
title NeoOptimize Defender AuditMode Recovery

net session >nul 2>&1
if not "%errorlevel%"=="0" (
  powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo.
echo NeoOptimize Defender AuditMode Recovery
echo This keeps Microsoft Defender enabled, but changes aggressive lab ASR/CFA policies to AuditMode.
echo.

powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -Command ^
  "$ErrorActionPreference='SilentlyContinue';" ^
  "Set-MpPreference -EnableControlledFolderAccess AuditMode;" ^
  "Set-MpPreference -EnableNetworkProtection AuditMode;" ^
  "$prefs=Get-MpPreference;" ^
  "$ids=@($prefs.AttackSurfaceReductionRules_Ids);" ^
  "if($ids.Count -gt 0){" ^
  "  $actions=@(); for($i=0;$i -lt $ids.Count;$i++){ $actions += 'AuditMode' };" ^
  "  Set-MpPreference -AttackSurfaceReductionRules_Ids $ids -AttackSurfaceReductionRules_Actions $actions;" ^
  "};" ^
  "Set-MpPreference -PUAProtection Enabled;" ^
  "Write-Host 'Defender remains enabled. ASR/CFA/NetworkProtection are now AuditMode.' -ForegroundColor Green"

echo.
echo Done. Download and run the new NeoOptimize installer again:
echo   http://192.168.122.1:8767/n.exe
echo.
pause
