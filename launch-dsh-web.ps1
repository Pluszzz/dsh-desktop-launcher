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

$port   = 3080
$bakedRepo = 'D:\CodeWork\deepseek-harness'
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
