@echo off
setlocal
title Home Edge Bootstrap - Desktop shortcut
set "HomeEdgeShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%HomeEdgeShell%" (
  where.exe pwsh.exe >nul 2>nul
  if errorlevel 1 (
    echo PowerShell is unavailable. Keep the complete package and retry after installing PowerShell for this user.
    pause
    exit /b 2
  )
  set "HomeEdgeShell=pwsh.exe"
)
"%HomeEdgeShell%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\create-desktop-shortcut.ps1" %*
set "HomeEdgeExit=%errorlevel%"
echo.
pause
exit /b %HomeEdgeExit%
