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
# Live files are in the Potassium *workspace* folder (scripts\ held stale copies).
$srcRoot = 'C:\Users\Revi\AppData\Local\Potassium\workspace'
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

# Keep the repo's copy of this script current (so the old shortcut uses the fixed one).
$repoScript = Join-Path $repoRoot 'Publish-PlayerTools.ps1'
if ($PSCommandPath -and ((Resolve-Path $PSCommandPath).Path -ne $repoScript) -and (Test-Path $repoRoot)) {
  Copy-Item -Force $PSCommandPath $repoScript
  Write-Host '==> Updated Publish-PlayerTools.ps1 in the repo'
}
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

# Build the file list from what is actually on this PC (so friends get exactly your version).
# Only code + whitelist ship. Saved settings/toggles (flag files, *.json prefs, profiles,
# hive webhooks, logs) never leave this PC.
$excludeName = '^(_|ForgeTools\.lua$|EggCodeDoorProbe\.lua$|slow_corr_probe\.lua$)'
$excludeLike = @('*.backup.*', '*.bak', '*.pending.*', '*.before-*', '*backup*', '*.v[0-9]*.*')
$shipExtra = @('whitelist.txt', 'whitelist.example.txt')
$names = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $ptSrc -File | ForEach-Object {
  $n = $_.Name
  $isCode = $n -like '*.lua' -or $n -like '*.iy'
  if (-not $isCode -and ($shipExtra -notcontains $n)) { return }
  if ($n -match $excludeName) { return }
  foreach ($pat in $excludeLike) { if ($n -like $pat) { return } }
  $names.Add($n)
}
$names = $names | Sort-Object
$fileList = @()
foreach ($n in $names) { $fileList += "PlayerTools/$n" }
$fileList += 'PlayerTools/backend'
$fileList += 'PlayerTools/version.json'
$ver.files = $fileList

$copied = 0
foreach ($n in $names) {
  Copy-Item -Force (Join-Path $ptSrc $n) (Join-Path $ptDst $n)
  $copied++
}
Write-Host "==> Copied $copied files from Potassium workspace (settings excluded)"

$bootSrc = Join-Path $srcRoot 'bootstrap.lua'
if (Test-Path $bootSrc) { Copy-Item -Force $bootSrc (Join-Path $repoRoot 'bootstrap.lua') } else { Write-Host '==> bootstrap.lua kept from repo' }
$ataraxiaEntry = Join-Path $srcRoot 'Ataraxia.lua'
if (Test-Path $ataraxiaEntry) {
  Copy-Item -Force $ataraxiaEntry (Join-Path $repoRoot 'Ataraxia.lua')
  Write-Host '==> Copied Ataraxia.lua (optional direct entry)'
}

# Friends get Ataraxia chrome by default. Never publish local-only markers.
Write-Utf8NoBom (Join-Path $ptDst 'backend') "ataraxia`n"
Write-Host '==> Wrote PlayerTools/backend = ataraxia (publish tree only)'
foreach ($junk in @('_dev_copy', '_hide_menu', '_tile_now', '_tile_alts_only', '_no_github_update', '_friend_build')) {
  $junkPath = Join-Path $ptDst $junk
  if (Test-Path $junkPath) { Remove-Item -Force $junkPath }
}

$verJson = ($ver | ConvertTo-Json -Depth 5) + [Environment]::NewLine
Write-Utf8NoBom (Join-Path $repoRoot 'version.json') $verJson
Write-Utf8NoBom (Join-Path $ptSrc 'version.json') $verJson
Write-Utf8NoBom (Join-Path $ptDst 'version.json') $verJson

# Keep package.json version in sync (regex only — never ConvertTo-Json the whole file;
# a corrupted description field once grew to 140MB+ and broke GitHub push).
$pkgPath = Join-Path $repoRoot 'package.json'
$pkgTemplate = @"
{
  "name": "playertools",
  "version": "{VERSION}",
  "private": true,
  "description": "Swordburst 2 PlayerTools — GitHub raw update feed (Neuublue-style)",
  "scripts": {
    "publish:updates": "powershell -ExecutionPolicy Bypass -File ./Publish-PlayerTools.ps1",
    "publish:updates:skip-bump": "powershell -ExecutionPolicy Bypass -File ./Publish-PlayerTools.ps1 -SkipVersionBump"
  }
}
"@
if (Test-Path $pkgPath) {
  $pkgRaw = [System.IO.File]::ReadAllText($pkgPath)
  if ($pkgRaw.Length -gt 8192 -or $pkgRaw -notmatch '"version"\s*:') {
    Write-Host '==> Replacing bloated or invalid package.json with minimal template'
    Write-Utf8NoBom $pkgPath ($pkgTemplate.Replace('{VERSION}', $ver.version))
  } else {
    $updated = [regex]::Replace(
      $pkgRaw,
      '"version"\s*:\s*"[^"]*"',
      ('"version": "' + $ver.version + '"'),
      1
    )
    Write-Utf8NoBom $pkgPath ($updated.TrimEnd() + [Environment]::NewLine)
  }
} else {
  Write-Utf8NoBom $pkgPath ($pkgTemplate.Replace('{VERSION}', $ver.version))
}

Set-Location $repoRoot

# Per-command identity only (never touch global git config).
$gitIdentity = @(
  '-c', 'user.email=nickb926@users.noreply.github.com',
  '-c', 'user.name=NickB926'
)

function Invoke-Git {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
  & git @gitIdentity @GitArgs
  if ($LASTEXITCODE -ne 0) {
    throw "git $($GitArgs -join ' ') failed (exit $LASTEXITCODE)"
  }
}

try {
  if (-not (Test-Path (Join-Path $repoRoot '.git'))) {
    git init
    if ($LASTEXITCODE -ne 0) { throw "git init failed" }
    git branch -M main
    gh repo create NickB926/playertools --public --source=. --remote=origin --push
    if ($LASTEXITCODE -ne 0) { throw "gh repo create failed" }
  } else {
    git add -A
    if ($LASTEXITCODE -ne 0) { throw "git add failed" }
    $status = git status --porcelain
    if (-not $status) {
      Write-Host 'No file changes after sync --- nothing to push.'
      exit 0
    }
    Invoke-Git commit -m "PlayerTools $($ver.version): $($ver.message)"
    git push -u origin HEAD
    if ($LASTEXITCODE -ne 0) { throw "git push failed (exit $LASTEXITCODE)" }
  }

  if ($Public) {
    gh repo edit NickB926/playertools --visibility public --accept-visibility-change-consequences
    if ($LASTEXITCODE -ne 0) { throw "gh repo edit failed" }
  }
} catch {
  Write-Host "==> Publish failed --- restoring version.json to $oldVersion"
  Write-Utf8NoBom $verPath $oldRaw
  throw
}

Write-Host ""
Write-Host "==> Published $($ver.version)  (was $oldVersion) --- pushed to GitHub"
Write-Host "Friend / reinstall (Ataraxia chrome by default):"
Write-Host 'loadstring(game:HttpGet("https://raw.githubusercontent.com/NickB926/playertools/main/bootstrap.lua"))()'
Write-Host "Or in-game: Settings -> GitHub updates -> Check / Apply"
