# install-shortcut.ps1
# Reusable installer for the DSH Web desktop shortcut.
# Copies of this folder can be moved to another machine and re-pointed with -Repo.
# Usage:
#   powershell -ExecutionPolicy Bypass -File install-shortcut.ps1 -Repo D:\code\deepseek-harness
#   powershell -ExecutionPolicy Bypass -File install-shortcut.ps1 -Repo D:\code\deepseek-harness -Port 3080 -ShortcutName "DSH Web"
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

# --- 1. resolve repo: -Repo param, else parent-of-this-folder, else current dir ---
if (-not $Repo) {
  $parent = Split-Path $here -Parent
  if (Test-IsCheckout $parent) { $Repo = $parent }
  elseif (Test-IsCheckout (Get-Location).Path) { $Repo = (Get-Location).Path }
  else {
    Write-Host "usage: $PSCommandPath -Repo <path-to-deepseek-harness> [-Port 3080] [-ShortcutName 'DeepSeek Harness']" -ForegroundColor Yellow
    exit 1
  }
}
if (-not (Test-IsCheckout $Repo)) {
  throw "not a dsh checkout: $Repo (missing $probe)"
}
$Repo = (Resolve-Path $Repo).Path
$url = "http://127.0.0.1:$Port"

# --- 2. write the launcher script from a template ---
$template = @'
# DSH Web launcher (portable)
# Starts the DeepSeek Harness web server (if not already running) and opens the GUI.
# Finds the checkout automatically, so this folder can be copied to any machine:
#   1. parent folder of this script IS the checkout (folder placed inside the repo)
#   2. repo-path.txt sidecar (written by install-shortcut.ps1 or the folder picker)
#   3. path baked in by install-shortcut.ps1 at install time
#   4. common locations under the user profile
#   5. shallow scan of every fixed drive root
#   6. interactive folder picker (choice is remembered in repo-path.txt)
$ErrorActionPreference = 'Stop'

$port   = __PORT__
$bakedRepo = '__REPO__'
$sidecar = Join-Path $PSScriptRoot 'repo-path.txt'
$probe   = 'apps\cli\src\bin.ts'

function Test-IsCheckout { param([string]$path) Test-Path (Join-Path $path $probe) }

function Resolve-Repo {
  # 1. this folder sits inside the checkout
  $parent = Split-Path $PSScriptRoot -Parent
  if (Test-IsCheckout $parent) { return $parent }
  # 2. remembered path
  if (Test-Path $sidecar) {
    $p = (Get-Content $sidecar -Raw).Trim()
    if (Test-IsCheckout $p) { return $p }
  }
  # 3. baked default
  if ($bakedRepo -and (Test-IsCheckout $bakedRepo)) { return $bakedRepo }
  # 4. common locations
  foreach ($c in @("$HOME\deepseek-harness", "$HOME\code\deepseek-harness", "$HOME\CodeWork\deepseek-harness", "$HOME\Documents\deepseek-harness", "$HOME\Desktop\deepseek-harness", "$HOME\Downloads\deepseek-harness")) {
    if (Test-IsCheckout $c) { return $c }
  }
  # 5. drive roots (shallow, cheap Test-Path only)
  foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null })) {
    foreach ($sub in @('deepseek-harness', 'CodeWork\deepseek-harness', 'code\deepseek-harness')) {
      $p = Join-Path $d.Root $sub
      if (Test-IsCheckout $p) { return $p }
    }
  }
  return $null
}

function Fail {
  param([string]$msg)
  $msg | Add-Content (Join-Path $PSScriptRoot 'launcher-error.log')
  if ([Environment]::UserInteractive) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($msg, 'DSH Web 启动失败') | Out-Null
  }
  exit 1
}

$repo = Resolve-Repo
if (-not $repo -and [Environment]::UserInteractive) {
  # 6. let the user pick the checkout once; remember it
  Add-Type -AssemblyName System.Windows.Forms
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description = '请选择 deepseek-harness 仓库文件夹（包含 apps\cli\src\bin.ts）'
  $dlg.SelectedPath = $HOME
  $dlg.ShowNewFolderButton = $false
  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and (Test-IsCheckout $dlg.SelectedPath)) {
    $repo = $dlg.SelectedPath
    Set-Content -Path $sidecar -Value $repo -Encoding UTF8
  }
}
if (-not $repo) { Fail "找不到 deepseek-harness 仓库（缺少 $probe）。请把本文件夹放进仓库目录，或运行 install-shortcut.cmd 重新安装。" }
if (-not (Test-Path (Join-Path $repo 'node_modules\tsx'))) { Fail "仓库缺少依赖：请先在 $repo 下运行 pnpm install。" }

function Test-PortOpen {
  $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
  return [bool]$c
}

if (-not (Test-PortOpen)) {
  $node = Join-Path $env:ProgramFiles 'nodejs\node.exe'
  if (-not (Test-Path $node)) { $node = (Get-Command node -ErrorAction SilentlyContinue).Source }
  if (-not $node) { Fail '未找到 Node.js：请先安装 Node.js 22 或更高版本。' }
  Start-Process -FilePath $node -ArgumentList @('--import', 'tsx/esm', 'apps/cli/src/bin.ts', 'web', '--port', "$port") -WorkingDirectory $repo -WindowStyle Minimized | Out-Null
  $deadline = (Get-Date).AddSeconds(60)
  while (-not (Test-PortOpen) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
  }
  if (-not (Test-PortOpen)) { Fail "服务启动超时：$port 端口 60 秒内未就绪，请查看最小化的服务窗口日志。" }
}

Start-Process "http://127.0.0.1:$port"
'@
$launcher = Join-Path $here 'launch-dsh-web.ps1'
$template = $template.Replace('__REPO__', $Repo).Replace('__PORT__', "$Port")
Set-Content -Path $launcher -Value $template -Encoding UTF8
Write-Step "launcher written: $launcher"

# remember the repo for the launcher's resolution step 2
Set-Content -Path (Join-Path $here 'repo-path.txt') -Value $Repo -NoNewline -Encoding UTF8
Write-Step "repo remembered: repo-path.txt"

# --- 3. icon: reuse dsh-web.ico, or rebuild it when absent ---
$ico = Join-Path $here 'dsh-web.ico'
if (-not (Test-Path $ico)) {
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
    Write-Host '[dsh-shortcut] dsh-web.ico missing and cannot be rebuilt (need favicon.svg, Edge, node); shortcut will use the default icon' -ForegroundColor Yellow
  }
}

# --- 4. create/refresh the desktop shortcut ---
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop "$ShortcutName.lnk"
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
$lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`""
$lnk.WorkingDirectory = $Repo
if (Test-Path $ico) { $lnk.IconLocation = $ico }
$lnk.Description = "Launch DeepSeek Harness Web GUI ($url)"
$lnk.Save()
Write-Step "shortcut ready: $lnkPath -> $url"
