# Publish PlayerTools to NickB926/playertools (GitHub raw update feed)
param(
  [string]$Version = '',
  [string]$Message = '',
  [switch]$Public
)

$ErrorActionPreference = 'Stop'
$srcRoot = 'C:\Users\Revi\AppData\Local\Potassium\scripts'
$repoRoot = 'C:\Users\Revi\Documents\playertools'
$ptSrc = Join-Path $srcRoot 'PlayerTools'
$ptDst = Join-Path $repoRoot 'PlayerTools'

if (-not (Test-Path $ptSrc)) { throw "Missing source $ptSrc" }
if (-not (Test-Path $repoRoot)) { New-Item -ItemType Directory -Force -Path $repoRoot | Out-Null }

# Sync tracked files from version.json (or copy core set)
$verPath = Join-Path $ptSrc 'version.json'
$ver = Get-Content $verPath -Raw | ConvertFrom-Json
if ($Version) {
  $ver.version = $Version
}
if ($Message) {
  $ver.message = $Message
}
elseif (-not $ver.message) {
  $ver.message = "PlayerTools $($ver.version)"
}

# Ensure PlayerTools dir in repo
if (Test-Path $ptDst) { Remove-Item -Recurse -Force $ptDst }
New-Item -ItemType Directory -Force -Path $ptDst | Out-Null

foreach ($rel in $ver.files) {
  if ($rel -eq 'version.json') { continue }
  $name = $rel -replace '^PlayerTools/', ''
  $from = Join-Path $ptSrc $name
  if (-not (Test-Path $from)) {
    Write-Warning "skip missing $from"
    continue
  }
  $to = Join-Path $ptDst $name
  $toDir = Split-Path $to -Parent
  if (-not (Test-Path $toDir)) { New-Item -ItemType Directory -Force -Path $toDir | Out-Null }
  Copy-Item -Force $from $to
  Write-Host "copied $rel"
}

# Root bootstrap + version
Copy-Item -Force (Join-Path $srcRoot 'bootstrap.lua') (Join-Path $repoRoot 'bootstrap.lua')
$ver | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $repoRoot 'version.json') -Encoding UTF8
$ver | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $ptSrc 'version.json') -Encoding UTF8
$ver | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $ptDst 'version.json') -Encoding UTF8

Set-Location $repoRoot
if (-not (Test-Path (Join-Path $repoRoot '.git'))) {
  git init
  gh repo create NickB926/playertools --private --source=. --remote=origin --push
} else {
  git add -A
  $status = git status --porcelain
  if (-not $status) {
    Write-Host 'No changes to publish.'
    exit 0
  }
  git commit -m "PlayerTools $($ver.version): $($ver.message)"
  git push -u origin HEAD
}

if ($Public) {
  gh repo edit NickB926/playertools --visibility public --accept-visibility-change-consequences
}

Write-Host ""
Write-Host "Published $($ver.version)"
Write-Host "Friend loadstring:"
Write-Host 'loadstring(game:HttpGet("https://raw.githubusercontent.com/NickB926/playertools/main/bootstrap.lua"))()'
