@echo off
setlocal
title Home Edge Bootstrap
set "HomeEdgeShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%HomeEdgeShell%" (
  where.exe pwsh.exe >nul 2>nul
  if errorlevel 1 (
    echo PowerShell is unavailable. Install PowerShell for this Windows user, then retry.
    pause
    exit /b 2
  )
  set "HomeEdgeShell=pwsh.exe"
)
if not exist "%~dp0scripts\launch-tui.ps1" (
  echo Home Edge Bootstrap files are missing.
  echo Extract the WHOLE ZIP first, then open start.cmd in the extracted folder.
  pause
  exit /b 2
)
"%HomeEdgeShell%" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\launch-tui.ps1" -Repo "%~dp0." %*
set "HomeEdgeExit=%errorlevel%"
if not "%HomeEdgeExit%"=="0" (
  echo.
  echo The guide stopped with exit code %HomeEdgeExit%. Read the message above.
  pause
)
exit /b %HomeEdgeExit%
