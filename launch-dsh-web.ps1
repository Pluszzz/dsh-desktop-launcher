# DSH Web launcher (portable, rc.7)
# Starts the DeepSeek Harness Web GUI through the globally installed `dsh` CLI
# (0.1.0-rc.7) if it is not already running, then opens the browser.
# Self-contained: no source checkout required.
#   C:\Users\pluszzz\AppData\Roaming\npm\dsh.cmd is baked in by install-shortcut.ps1; PATH/APPDATA fallbacks cover
#   other machines.
$ErrorActionPreference = 'Stop'

$port      = 3080
$bakedDsh  = 'C:\Users\pluszzz\AppData\Roaming\npm\dsh.cmd'
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
