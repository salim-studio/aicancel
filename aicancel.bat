@echo off
REM =====================================================================
REM  aicancel v1.1.0 - Cancel Windows AI
REM  Copyright (c) 2026 salim-slimani. Licensed under the MIT License.
REM  Project: https://github.com/salim-studio/aicancel
REM  Launcher: requests admin rights and runs aicancel.ps1.
REM  Usage: aicancel.bat [-all] [-scan] [-revert]
REM =====================================================================

NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
  echo Requesting administrator rights...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -ArgumentList '%*' -Verb RunAs"
  exit /b
)

set SCRIPT=%~dp0aicancel.ps1
if "%1"=="-all" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -NonInteractive -All -Backup -EnableLog
) else if "%1"=="-scan" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -ScanOnly -NonInteractive -All
) else if "%1"=="-revert" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -NonInteractive -All -Revert
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Backup -EnableLog
)
pause
