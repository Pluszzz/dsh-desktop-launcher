# install-shortcut.ps1
# Installer for the DSH Web desktop shortcut (rc.7 mode).
# Requires the dsh CLI installed globally: npm install -g @deepseek-ai/dsh
# Usage:
#   powershell -ExecutionPolicy Bypass -File install-shortcut.ps1
#   powershell -ExecutionPolicy Bypass -File install-shortcut.ps1 -Repo D:\code\deepseek-harness -Port 3080 -ShortcutName "DSH Web"
#   -Repo is optional: it is only used to rebuild dsh-web.ico from the checkout's
#   favicon.svg when the icon file is missing.
param(
  [string]$Repo,
  [int]$Port = 3080,
  [string]$ShortcutName = 'DeepSeek Harness'
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$probe = 'apps\cli\src\bin.ts'

function Write-Step { param([string]$msg) Write-Host "[dsh-shortcut] $msg" -ForegroundColor Cyan }
function Test-IsCheckout { param([string]$path) Test-Path (Join-Path $path $probe) }

# --- 1. resolve the dsh CLI (npm global install) ---
$dshCandidates = @()
foreach ($c in (Get-Command dsh -ErrorAction SilentlyContinue)) {
  if ($c.Source -match '\.(cmd|exe|bat)$') { $dshCandidates += $c.Source }
}
$appdataDsh = Join-Path $env:APPDATA 'npm\dsh.cmd'
if (Test-Path $appdataDsh) { $dshCandidates += $appdataDsh }
$dsh = $dshCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $dsh) {
  Write-Host '未找到 dsh 命令。请先安装：npm install -g @deepseek-ai/dsh' -ForegroundColor Yellow
  exit 1
}
Write-Step "dsh CLI: $dsh"

# --- 2. write the launcher script from a template ---
$template = @'
# DSH Web launcher (portable, rc.7)
# Starts the DeepSeek Harness Web GUI through the globally installed `dsh` CLI
# (0.1.0-rc.7) if it is not already running, then opens the browser.
# Self-contained: no source checkout required.
#   __DSH__ is baked in by install-shortcut.ps1; PATH/APPDATA fallbacks cover
#   other machines.
$ErrorActionPreference = 'Stop'

$port      = __PORT__
$bakedDsh  = '__DSH__'
$here      = $PSScriptRoot
$log       = Join-Path $here 'launcher-error.log'

function Test-PortOpen {
  $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
  return [bool]$c
}

function Resolve-Dsh {
  $found = @()
  if ($bakedDsh -and (Test-Path $bakedDsh)) { $found += $bakedDsh }
  foreach ($c in (Get-Command dsh -ErrorAction SilentlyContinue)) {
    if ($c.Source -match '\.(cmd|exe|bat)$') { $found += $c.Source }
  }
  $appdata = Join-Path $env:APPDATA 'npm\dsh.cmd'
  if (Test-Path $appdata) { $found += $appdata }
  return $found | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

function Fail {
  param([string]$msg)
  try { $msg | Add-Content $log } catch {}
  if ([Environment]::UserInteractive) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($msg, 'DSH Web 启动失败') | Out-Null
  }
  exit 1
}

$dsh = Resolve-Dsh
if (-not $dsh) { Fail '未找到 dsh 命令。请先安装：npm install -g @deepseek-ai/dsh' }

if (-not (Test-PortOpen)) {
  Start-Process -FilePath $dsh -ArgumentList @('web', '--port', "$port") -WindowStyle Minimized | Out-Null
  $deadline = (Get-Date).AddSeconds(60)
  while (-not (Test-PortOpen) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
  }
  if (-not (Test-PortOpen)) { Fail "服务启动超时：$port 端口 60 秒内未就绪，请查看最小化的服务窗口日志。" }
}

Start-Process "http://127.0.0.1:$port"
'@
$launcher = Join-Path $here 'launch-dsh-web.ps1'
$template = $template.Replace('__DSH__', $dsh).Replace('__PORT__', "$Port")
Set-Content -Path $launcher -Value $template -Encoding UTF8
Write-Step "launcher written: $launcher"

# --- 3. icon: reuse dsh-web.ico, or rebuild it when absent (needs -Repo + Edge + node) ---
$ico = Join-Path $here 'dsh-web.ico'
if (-not (Test-Path $ico)) {
  if ($Repo -and (Test-IsCheckout $Repo)) {
    $favicon = Join-Path $Repo 'apps\web\public\favicon.svg'
    $edge = @("$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe", "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ((Test-Path $favicon) -and $edge -and (Get-Command node -ErrorAction SilentlyContinue)) {
      Write-Step 'rebuilding icon from favicon.svg ...'
      $xml = [xml](Get-Content $favicon -Raw)
      Set-Content -Path (Join-Path $here 'whale-path.txt') -Value $xml.svg.path.GetAttribute('d') -NoNewline -Encoding UTF8
      node (Join-Path $here 'make-icon.mjs') | Out-Null
      $png512 = Join-Path $here 'dsh-web-512.png'
      $fileUrl = 'file:///' + (($here -replace '\\', '/') -replace '^/', '') + '/dsh-web.svg'
      $p = Start-Process -FilePath $edge -ArgumentList @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1', '--window-size=512,512', "--screenshot=$png512", '--default-background-color=00000000', "--user-data-dir=$env:TEMP\dsh-edge-icon", '--no-first-run', '--no-default-browser-check', $fileUrl) -Wait -PassThru -NoNewindow
      if ($p.ExitCode -ne 0) { throw "edge render failed (exit $($p.ExitCode))" }
      Add-Type -AssemblyName System.Drawing
      $src = New-Object System.Drawing.Bitmap($png512)
      foreach ($s in @(16, 32, 48, 64, 128, 256)) {
        $dst = New-Object System.Drawing.Bitmap($s, $s)
        $g = [System.Drawing.Graphics]::FromImage($dst)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.Clear([System.Drawing.Color]::Transparent)
        $g.DrawImage($src, 0, 0, $s, $s)
        $g.Dispose()
        $dst.Save((Join-Path $here "dsh-web-$s.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $dst.Dispose()
      }
      $src.Dispose()
      node (Join-Path $here 'make-icon.mjs') --pack | Out-Null
      Write-Step "icon rebuilt: $ico"
    } else {
      Write-Host '[dsh-shortcut] dsh-web.ico missing and cannot be rebuilt (need -Repo checkout, Edge, node); shortcut will use the default icon' -ForegroundColor Yellow
    }
  } else {
    Write-Host '[dsh-shortcut] dsh-web.ico missing; pass -Repo <deepseek-harness checkout> to rebuild it, shortcut will use the default icon' -ForegroundColor Yellow
  }
}

# --- 4. create/refresh the desktop shortcut ---
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop "$ShortcutName.lnk"
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
$lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`" -AppMode"
$lnk.WorkingDirectory = $here
if (Test-Path $ico) { $lnk.IconLocation = $ico }
$lnk.Description = "Launch DeepSeek Harness Web GUI (http://127.0.0.1:$Port)"
$lnk.Save()
Write-Step "shortcut ready: $lnkPath -> http://127.0.0.1:$Port"

# --- 5. tray manager: write the hidden launcher and a desktop shortcut ---
$vbsPath = Join-Path $here 'dsh-tray.vbs'
if (-not (Test-Path $vbsPath)) {
  $vbs = @'
' dsh-tray.vbs - launch dsh-tray.ps1 hidden (no console window)
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptDir & "\dsh-tray.ps1""", 0, False
'@
  Set-Content -Path $vbsPath -Value $vbs -Encoding ASCII
  Write-Step "tray launcher written: $vbsPath"
}
$trayLnkPath = Join-Path $desktop 'DSH Web 托盘.lnk'
$ws = New-Object -ComObject WScript.Shell
$trayLnk = $ws.CreateShortcut($trayLnkPath)
$trayLnk.TargetPath = "$env:windir\System32\wscript.exe"
$trayLnk.Arguments = "`"$vbsPath`""
$trayLnk.WorkingDirectory = $here
if (Test-Path $ico) { $trayLnk.IconLocation = $ico }
$trayLnk.Description = 'DSH Web 系统托盘管理器（右键菜单管理服务；开机自启在托盘菜单里勾选）'
$trayLnk.Save()
Write-Step "tray shortcut ready: $trayLnkPath (auto-start is a tray menu checkbox, not set by this installer)"



