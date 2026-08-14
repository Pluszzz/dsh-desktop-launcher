@echo off
rem install-shortcut.cmd - double-click to create/refresh the desktop shortcut.
rem Place this folder inside the deepseek-harness checkout, then double-click here:
rem   <repo>\dsh-launcher\install-shortcut.cmd
rem Or pass the repo path: install-shortcut.cmd D:\path\to\deepseek-harness
setlocal
set "HERE=%~dp0"
set "PARENT=%HERE%.."
set "REPO=%~1"

if "%REPO%"=="" if exist "%PARENT%apps\cli\src\bin.ts" set "REPO=%PARENT%"
if "%REPO%"=="" if exist "%CD%\apps\cli\src\bin.ts" set "REPO=%CD%"

if not "%REPO%"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%install-shortcut.ps1" -Repo "%REPO%"
) else (
  echo Not a deepseek-harness checkout found. Usage:
  echo   install-shortcut.cmd D:\path\to\deepseek-harness
)
echo.
pause
