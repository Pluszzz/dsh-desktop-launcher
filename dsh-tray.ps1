# dsh-tray.ps1 — system tray manager for the DSH web service.
#   - tray icon with the whale logo (dsh-web.ico)
#   - left click: toggle the server console window (show / minimize)
#   - right-click menu: open GUI, show/hide window, restart, stop, exit
# Launched hidden via wscript (see install-shortcut.ps1); must run in an
# STA thread ([System.Windows.Forms.Application]::Run requires it).
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ShowWindow for toggling the server's console window.
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DshNative {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$icoPath = Join-Path $here 'dsh-web.ico'
$port    = 3080
$url     = "http://127.0.0.1:$port"
$log     = Join-Path $here 'dsh-tray.log'

function Write-Log { param([string]$msg) try { "$(Get-Date -Format 'HH:mm:ss') $msg" | Add-Content $log } catch {} }

# ── server management ────────────────────────────────────────────────────────

function Test-PortOpen {
  $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
  return [bool]$c
}

function Get-ServerProcess {
  $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $c) { return $null }
  return Get-CimInstance Win32_Process -Filter "ProcessId = $($c.OwningProcess)"
}

# Resolve how to start the server: global dsh install first, then a checkout.
function Resolve-StartArgs {
  $globalDsh = Join-Path $env:APPDATA 'npm\node_modules\@deepseek-ai\dsh\lib\bin.js'
  if (Test-Path $globalDsh) {
    return @{ Args = @($globalDsh, 'web', '--port', "$port"); WorkDir = $null }
  }
  $probe = 'apps\cli\src\bin.ts'
  $repo = $null
  $sidecar = Join-Path $here 'repo-path.txt'
  if (Test-Path $sidecar) {
    $p = (Get-Content $sidecar -Raw).Trim()
    if (Test-Path (Join-Path $p $probe)) { $repo = $p }
  }
  if (-not $repo -and (Test-Path (Join-Path (Split-Path $here -Parent) $probe))) { $repo = Split-Path $here -Parent }
  if ($repo) {
    return @{ Args = @('--import', 'tsx/esm', (Join-Path $repo $probe), 'web', '--port', "$port"); WorkDir = $repo }
  }
  return $null
}

# Start the server if not running; returns the process object (or $null when already up).
function Start-Server {
  if (Test-PortOpen) { return $null }
  $node = Join-Path $env:ProgramFiles 'nodejs\node.exe'
  if (-not (Test-Path $node)) { $node = (Get-Command node -ErrorAction SilentlyContinue).Source }
  if (-not $node) { Write-Log 'node not found'; return $null }
  $start = Resolve-StartArgs
  if (-not $start) { Write-Log 'no dsh found (global install or checkout)'; return $null }
  try {
    if ($start.WorkDir) {
      $p = Start-Process -FilePath $node -ArgumentList $start.Args -WorkingDirectory $start.WorkDir -WindowStyle Hidden -PassThru
    } else {
      $p = Start-Process -FilePath $node -ArgumentList $start.Args -WindowStyle Hidden -PassThru
    }
    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-PortOpen) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    Write-Log "server started pid=$($p.Id) portOpen=$(Test-PortOpen)"
    return $p
  } catch {
    Write-Log "start failed: $_"
    return $null
  }
}

function Stop-Server {
  $p = Get-ServerProcess
  if ($p) { Stop-Process -Id $p.ProcessId -Force; Write-Log "server stopped pid=$($p.ProcessId)" }
}

function Restart-Server {
  Stop-Server
  Start-Sleep -Seconds 2
  Start-Server
  Start-Process $url
}

# Console window handle of the running server (0 when unavailable).
function Get-ConsoleHandle {
  $p = Get-ServerProcess
  if (-not $p) { return 0 }
  $proc = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
  if (-not $proc) { return 0 }
  $proc.Refresh()
  return $proc.MainWindowHandle
}

function Show-ConsoleWindow { $h = Get-ConsoleHandle; if ($h -ne 0) { [DshNative]::ShowWindow($h, 9) | Out-Null } } # SW_RESTORE
function Hide-ConsoleWindow { $h = Get-ConsoleHandle; if ($h -ne 0) { [DshNative]::ShowWindow($h, 0) | Out-Null } }
function Toggle-ConsoleWindow {
  $p = Get-ServerProcess
  if (-not $p) { Start-Server; Start-Sleep -Seconds 2; Start-Process $url; return }
  $h = Get-ConsoleHandle
  if ($h -eq 0) { Start-Process $url; return }
  # ShowWindow(SW_HIDE) returns the PREVIOUS visibility: nonzero = was visible.
  $wasVisible = [DshNative]::ShowWindow($h, 0)
  if (-not $wasVisible) { [DshNative]::ShowWindow($h, 9) | Out-Null } # was hidden -> restore
}

function Open-Web { Start-Process msedge.exe -ArgumentList "--app=http://127.0.0.1:$port" }

# ── auto-start support (tray menu toggle, never set automatically) ──────────

$vbsPath   = Join-Path $here 'dsh-tray.vbs'
$startupDir = [Environment]::GetFolderPath('Startup')
$startupLnk = Join-Path $startupDir 'DSH Web Tray.lnk'

function Ensure-TrayVbs {
  if (Test-Path $vbsPath) { return }
  $content = @'
' dsh-tray.vbs - launch dsh-tray.ps1 hidden (no console window)
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptDir & "\dsh-tray.ps1""", 0, False
'@
  Set-Content -Path $vbsPath -Value $content -Encoding ASCII
}

# ── tray UI ──────────────────────────────────────────────────────────────────

$notify = New-Object System.Windows.Forms.NotifyIcon
try { $notify.Icon = New-Object System.Drawing.Icon($icoPath) } catch { Write-Log "icon load failed: $_" }
$notify.Text = 'DSH Web'
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$miOpen  = New-Object System.Windows.Forms.ToolStripMenuItem('打开 Web GUI')
$miOpen.add_Click({ Open-Web })

$miShow  = New-Object System.Windows.Forms.ToolStripMenuItem('显示服务窗口')
$miShow.add_Click({ Show-ConsoleWindow })

$miHide  = New-Object System.Windows.Forms.ToolStripMenuItem('隐藏服务窗口')
$miHide.add_Click({ Hide-ConsoleWindow })

$miRestart = New-Object System.Windows.Forms.ToolStripMenuItem('重启服务')
$miRestart.add_Click({ Restart-Server })

$miStop  = New-Object System.Windows.Forms.ToolStripMenuItem('停止服务')
$miStop.add_Click({ Stop-Server })

$miExit  = New-Object System.Windows.Forms.ToolStripMenuItem('退出（停止服务）')
$miExit.add_Click({
  Stop-Server
  $notify.Visible = $false
  $notify.Dispose()
  [System.Windows.Forms.Application]::Exit()
})

$miAutostart = New-Object System.Windows.Forms.ToolStripMenuItem('开机自启（登录时自动启动 DSH 服务）')
$miAutostart.CheckOnClick = $true
$miAutostart.add_Click({
  Ensure-TrayVbs
  $ws = New-Object -ComObject WScript.Shell
  if ($miAutostart.Checked) {
    $lnk = $ws.CreateShortcut($startupLnk)
    $lnk.TargetPath = "$env:windir\System32\wscript.exe"
    $lnk.Arguments = "`"$vbsPath`""
    $lnk.IconLocation = $icoPath
    $lnk.Description = 'DSH Web 系统托盘管理器'
    $lnk.Save()
    Write-Log 'auto-start enabled'
  } else {
    if (Test-Path $startupLnk) { Remove-Item $startupLnk -Force; Write-Log 'auto-start disabled' }
  }
})
$menu.add_Opening({ $miAutostart.Checked = (Test-Path $startupLnk) })

$menu.Items.Add($miOpen) | Out-Null
$menu.Items.Add($miShow) | Out-Null
$menu.Items.Add($miHide) | Out-Null
$menu.Items.Add($miRestart) | Out-Null
$menu.Items.Add($miStop) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$menu.Items.Add($miAutostart) | Out-Null
$menu.Items.Add($miExit) | Out-Null
$notify.ContextMenuStrip = $menu

$notify.add_MouseClick({
  param($sender, $e)
  if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Toggle-ConsoleWindow }
})

# Boot: make sure the server is up and open the GUI, then stay resident.
Write-Log 'tray started'
$server = Start-Server
Start-Process msedge.exe -ArgumentList "--app=http://127.0.0.1:$port"

[System.Windows.Forms.Application]::Run()


