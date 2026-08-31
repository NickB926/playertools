# Publish PlayerTools to NickB926/playertools (same idea as discord-lite npm run publish:updates)
# Usage:
#   npm run publish:updates
#   npm run publish:updates -- -Message "fixed tribute ping"
#   npm run publish:updates -- -SkipVersionBump
#   .\Publish-PlayerTools.ps1 -Version 1.2.0 -Message "big drop"
param(
  [string]$Version = '',
  [string]$Message = '',
  [switch]$SkipVersionBump,
  [switch]$Public
)

$ErrorActionPreference = 'Stop'
$srcRoot = 'C:\Users\Revi\AppData\Local\Potassium\scripts'
$repoRoot = 'C:\Users\Revi\Documents\playertools'
$ptSrc = Join-Path $srcRoot 'PlayerTools'
$ptDst = Join-Path $repoRoot 'PlayerTools'
$utf8 = New-Object System.Text.UTF8Encoding $false

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Bump-PatchVersion([string]$v) {
  if ($v -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
    throw "version.json version must look like 1.0.0 (got '$v')"
  }
  $major = [int]$Matches[1]
  $minor = [int]$Matches[2]
  $patch = [int]$Matches[3] + 1
  return "$major.$minor.$patch"
}

if (-not (Test-Path $ptSrc)) { throw "Missing source $ptSrc" }
if (-not (Test-Path $repoRoot)) { New-Item -ItemType Directory -Force -Path $repoRoot | Out-Null }

$verPath = Join-Path $ptSrc 'version.json'
$oldRaw = Get-Content $verPath -Raw
$ver = $oldRaw | ConvertFrom-Json
$oldVersion = [string]$ver.version

if ($Version) {
  $ver.version = $Version
} elseif (-not $SkipVersionBump) {
  $ver.version = Bump-PatchVersion $oldVersion
  Write-Host "==> Bumping $oldVersion -> $($ver.version)"
} else {
  Write-Host "==> Keeping version $($ver.version) (-SkipVersionBump)"
}

if ($Message) {
  $ver.message = $Message
} elseif (-not $ver.message -or $ver.message -eq '') {
  $ver.message = "PlayerTools $($ver.version)"
}

Write-Host "==> Publishing PlayerTools $($ver.version): $($ver.message)"

if (Test-Path $ptDst) { Remove-Item -Recurse -Force $ptDst }
New-Item -ItemType Directory -Force -Path $ptDst | Out-Null

$copied = 0
foreach ($rel in $ver.files) {
  if ($rel -eq 'PlayerTools/version.json' -or $rel -eq 'version.json') { continue }
  $name = $rel -replace '^PlayerTools/', ''
  $from = Join-Path $ptSrc $name
  if (-not (Test-Path $from)) { Write-Warning "skip missing $from"; continue }
  $to = Join-Path $ptDst $name
  $toDir = Split-Path $to -Parent
  if (-not (Test-Path $toDir)) { New-Item -ItemType Directory -Force -Path $toDir | Out-Null }
  Copy-Item -Force $from $to
  $copied++
}
Write-Host "==> Copied $copied files from Potassium scripts"

Copy-Item -Force (Join-Path $srcRoot 'bootstrap.lua') (Join-Path $repoRoot 'bootstrap.lua')
$verJson = ($ver | ConvertTo-Json -Depth 5) + [Environment]::NewLine
Write-Utf8NoBom (Join-Path $repoRoot 'version.json') $verJson
Write-Utf8NoBom (Join-Path $ptSrc 'version.json') $verJson
Write-Utf8NoBom (Join-Path $ptDst 'version.json') $verJson

# Keep package.json version in sync for npm style
$pkgPath = Join-Path $repoRoot 'package.json'
if (Test-Path $pkgPath) {
  $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json
  $pkg.version = $ver.version
  Write-Utf8NoBom $pkgPath (($pkg | ConvertTo-Json -Depth 5) + [Environment]::NewLine)
}

Set-Location $repoRoot
try {
  if (-not (Test-Path (Join-Path $repoRoot '.git'))) {
    git init
    git branch -M main
    gh repo create NickB926/playertools --public --source=. --remote=origin --push
  } else {
    git add -A
    $status = git status --porcelain
    if (-not $status) {
      Write-Host 'No file changes after sync --- nothing to push.'
      exit 0
    }
    git commit -m "PlayerTools $($ver.version): $($ver.message)"
    git push -u origin HEAD
  }

  if ($Public) {
    gh repo edit NickB926/playertools --visibility public --accept-visibility-change-consequences
  }
} catch {
  Write-Host "==> Publish failed --- restoring version.json to $oldVersion"
  Write-Utf8NoBom $verPath $oldRaw
  throw
}

Write-Host ""
Write-Host "==> Published $($ver.version)  (was $oldVersion)"
Write-Host "Friend / reinstall:"
Write-Host 'loadstring(game:HttpGet("https://raw.githubusercontent.com/NickB926/playertools/main/bootstrap.lua"))()'
Write-Host "Or in-game: Settings --- GitHub updates --- Check / Apply"
