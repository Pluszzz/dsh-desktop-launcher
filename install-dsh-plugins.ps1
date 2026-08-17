# install-dsh-plugins.ps1
# One-click installer for the dsh-web-ui plugin pack into the web profile.
# Handles the ERR_PNPM_IGNORED_BUILDS allowBuilds fix automatically.
# Usage:
#   powershell -ExecutionPolicy Bypass -File install-dsh-plugins.ps1
#   powershell -ExecutionPolicy Bypass -File install-dsh-plugins.ps1 -Repo D:\code\deepseek-harness [-Version 0.1.10]
param(
  [string]$Repo,
  [string]$Version = '0.1.10'
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$probe = 'apps\cli\src\bin.ts'

if (-not $Repo) {
  if (Test-Path $probe) { $Repo = (Get-Location).Path }
  elseif (Test-Path (Join-Path (Split-Path $here -Parent) $probe)) { $Repo = Split-Path $here -Parent }
  else {
    Write-Host "usage: $PSCommandPath -Repo <path-to-deepseek-harness>" -ForegroundColor Yellow
    exit 1
  }
}
$Repo = (Resolve-Path $Repo).Path
$spec = "@linxin666/dsh-web-ui-all@$Version"
$profile = Join-Path $HOME '.dsh\profiles\web'
$yaml = Join-Path $profile 'pnpm-workspace.yaml'

function Invoke-AddPlugin {
  Push-Location $Repo
  try {
    node --import tsx/esm apps/cli/src/bin.ts plugin --profile web add $spec 2>&1 | Out-Host
  } finally {
    Pop-Location
  }
  return $LASTEXITCODE
}

Write-Host "[dsh-plugins] installing $spec into web profile (repo: $Repo)" -ForegroundColor Cyan
$code = Invoke-AddPlugin

if ($code -ne 0 -and (Test-Path $yaml)) {
  $content = Get-Content $yaml -Raw
  if ($content -match 'set this to true or false') {
    Write-Host '[dsh-plugins] build scripts blocked -> allowing cloudflared / cpu-features / ssh2 ...' -ForegroundColor Cyan
    Set-Content -Path $yaml -Value ($content -replace 'set this to true or false', 'true') -Encoding UTF8
    $code = Invoke-AddPlugin
  }
}

if ($code -ne 0) {
  Write-Host "[dsh-plugins] FAILED (exit $code)" -ForegroundColor Red
  exit $code
}
Write-Host '[dsh-plugins] OK. Restart dsh web (desktop shortcut) to activate the plugins.' -ForegroundColor Green
