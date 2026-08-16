@echo off
rem install-shortcut.cmd - double-click to create/refresh the desktop shortcut.
rem Requires the dsh CLI installed globally: npm install -g @deepseek-ai/dsh
rem Optional args are forwarded to install-shortcut.ps1, e.g.:
rem   install-shortcut.cmd -Repo D:\path\to\deepseek-harness -ShortcutName "DSH Web"
setlocal
set "HERE=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%install-shortcut.ps1" %*
echo.
pause
