@echo off
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0nullclaw.ps1" %*
