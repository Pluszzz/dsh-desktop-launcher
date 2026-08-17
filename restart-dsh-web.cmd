@echo off
rem restart-dsh-web.cmd - force-restart the DSH web server.
rem Kills whatever listens on port 3080 (the old rc.5 source process is a
rem common leftover), then relaunches through launch-dsh-web.ps1 (rc.6).
powershell -NoProfile -ExecutionPolicy Bypass -Command "$c = Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue; if ($c) { Write-Host ('[restart-dsh-web] killing PID ' + $c.OwningProcess) -ForegroundColor Cyan; Stop-Process -Id $c.OwningProcess -Force; Start-Sleep -Seconds 2 } else { Write-Host '[restart-dsh-web] nothing on 3080' -ForegroundColor Cyan }; & '%~dp0launch-dsh-web.ps1'"
