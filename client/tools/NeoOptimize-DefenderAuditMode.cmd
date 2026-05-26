@echo off
setlocal EnableExtensions
title NeoOptimize Defender Lab Recovery

net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo Administrator privileges are required.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

set "ENGINE=%ProgramFiles%\NeoOptimize\program\NeoOptimize.ps1"
if exist "%ENGINE%" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" -Action DefenderAuditMode
  exit /b %errorlevel%
)

echo.
echo NeoOptimize Defender Lab Recovery
echo.
echo This keeps Microsoft Defender enabled, but moves aggressive lab
echo Controlled Folder Access, Network Protection, and configured ASR rules
echo to AuditMode. Use only after an old lab hardening run made Windows
echo Security too strict.
echo.
choice /C YN /N /M "Continue? [Y/N] "
if errorlevel 2 exit /b 0

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Continue';" ^
  "try { Set-MpPreference -EnableControlledFolderAccess AuditMode -ErrorAction Stop; Write-Host '[OK] Controlled Folder Access AuditMode' -ForegroundColor Green } catch { Write-Host ('[WARN] CFA unchanged: ' + $_.Exception.Message) -ForegroundColor Yellow };" ^
  "try { Set-MpPreference -EnableNetworkProtection AuditMode -ErrorAction Stop; Write-Host '[OK] Network Protection AuditMode' -ForegroundColor Green } catch { Write-Host ('[WARN] Network Protection unchanged: ' + $_.Exception.Message) -ForegroundColor Yellow };" ^
  "try { $prefs=Get-MpPreference -ErrorAction Stop; $ids=@($prefs.AttackSurfaceReductionRules_Ids); if($ids.Count -gt 0){ $actions=@(); for($i=0;$i -lt $ids.Count;$i++){ $actions += 'AuditMode' }; Set-MpPreference -AttackSurfaceReductionRules_Ids $ids -AttackSurfaceReductionRules_Actions $actions -ErrorAction Stop; Write-Host '[OK] ASR rules AuditMode' -ForegroundColor Green } else { Write-Host '[INFO] No configured ASR rules.' -ForegroundColor Cyan } } catch { Write-Host ('[WARN] ASR unchanged: ' + $_.Exception.Message) -ForegroundColor Yellow };" ^
  "Write-Host 'Defender realtime protection remains enabled.' -ForegroundColor Green"

echo.
echo Done. Re-run NeoOptimize or the installer after this recovery.
pause
