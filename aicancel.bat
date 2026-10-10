@echo off
REM aicancel launcher - يشغل كمسؤول تلقائيا + يتجاوز ExecutionPolicy
REM Usage: aicancel.bat [-all] [-scan] [-revert]

NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
  echo طلب صلاحيات المسؤول...
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
