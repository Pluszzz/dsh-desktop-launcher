@echo off
rem install-dsh-plugins.cmd - double-click to install the dsh-web-ui plugin pack
rem into the web profile. Place this folder inside the deepseek-harness checkout
rem (or pass the repo path as the first argument), then double-click.
setlocal
set "HERE=%~dp0"
set "PARENT=%HERE%.."
set "REPO=%~1"

if "%REPO%"=="" if exist "%PARENT%apps\cli\src\bin.ts" set "REPO=%PARENT%"
if "%REPO%"=="" if exist "%CD%\apps\cli\src\bin.ts" set "REPO=%CD%"

if not "%REPO%"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%install-dsh-plugins.ps1" -Repo "%REPO%"
) else (
  echo Not a deepseek-harness checkout found. Usage:
  echo   install-dsh-plugins.cmd D:\path\to\deepseek-harness
)
echo.
pause
