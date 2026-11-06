#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Builds, versions, and publishes an OTA content pack for SpotRush to a
  GitHub Release on your existing repo. Windows/PowerShell twin of
  publish_ota.sh.

.USAGE
  .\scripts\dev\publish_ota.ps1 1.0.62 "fix lobby compile and OTA export"

.REQUIRES
  - Godot 4.7 editor on PATH as `godot`, or set $env:GODOT to its full .exe path
  - GitHub CLI (`gh`) authenticated with `gh auth login`
  - Run from inside the repo checkout, or set $env:GITHUB_REPO = "owner/repo"
  - The Android export preset must exist in export_presets.cfg
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Version,

    [Parameter(Position = 1)]
    [string]$Notes = "OTA update $Version"
)

$ErrorActionPreference = "Stop"
$GodotBin = if ($env:GODOT) { $env:GODOT } else { "godot" }
$ProjectPath = (Get-Location).Path
$OutDir = "ota_builds"
$PckName = "content.pck"
$ManifestName = "manifest.json"
$Tag = "ota-$Version"

$Repo = $env:GITHUB_REPO
if (-not $Repo) {
    $Repo = (gh repo view --json nameWithOwner -q .nameWithOwner) 2>$null
}
if (-not $Repo) {
    throw "Could not determine the GitHub repo. Run this inside your checkout or set `$env:GITHUB_REPO = 'owner/repo'."
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$LogBase = Join-Path $env:TEMP "spotrush-ota-$Version"
$ValidationOut = "$LogBase-preflight.stdout.log"
$ValidationErr = "$LogBase-preflight.stderr.log"
$ExportOut = "$LogBase-export.stdout.log"
$ExportErr = "$LogBase-export.stderr.log"
foreach ($LogPath in @($ValidationOut, $ValidationErr, $ExportOut, $ExportErr)) {
    if (Test-Path $LogPath) { Remove-Item $LogPath -Force }
}

# Godot can return exit code 0 after printing script parse errors during export.
# Run an editor scan first, then inspect both exit code and diagnostic output.
Write-Host "==> Validating project scripts before OTA export..."
$ValidationArgs = "--headless --editor --path `"$ProjectPath`" --quit"
$ValidationProc = Start-Process -FilePath $GodotBin `
    -ArgumentList $ValidationArgs `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $ValidationOut `
    -RedirectStandardError $ValidationErr

$ValidationText = ""
foreach ($LogPath in @($ValidationOut, $ValidationErr)) {
    if (Test-Path $LogPath) { $ValidationText += (Get-Content -Raw $LogPath) + "`n" }
}
if ($ValidationText) { Write-Host $ValidationText }
$ScriptFailurePattern = '(?im)(SCRIPT ERROR:|Parse Error:|Failed to load script|Failed to load resource)'
if ($ValidationProc.ExitCode -ne 0 -or $ValidationText -match $ScriptFailurePattern) {
    throw "GDScript validation failed. OTA export and publishing were stopped. Fix the errors above first."
}

Write-Host "==> Exporting content pack for version $Version..."
$PckFullPath = Join-Path $ProjectPath "$OutDir\$PckName"
if (Test-Path $PckFullPath) { Remove-Item $PckFullPath -Force }
$ExportArgs = "--headless --export-pack Android `"$PckFullPath`""
$ExportProc = Start-Process -FilePath $GodotBin `
    -ArgumentList $ExportArgs `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $ExportOut `
    -RedirectStandardError $ExportErr

$ExportText = ""
foreach ($LogPath in @($ExportOut, $ExportErr)) {
    if (Test-Path $LogPath) { $ExportText += (Get-Content -Raw $LogPath) + "`n" }
}
if ($ExportText) { Write-Host $ExportText }
$ExportFailurePattern = '(?im)(SCRIPT ERROR:|Parse Error:|Failed to load script|Failed to load resource)'
if ($ExportProc.ExitCode -ne 0 -or $ExportText -match $ExportFailurePattern) {
    throw "Godot reported a script/resource/export error. OTA publishing was stopped. Fix the errors above first."
}
if (-not (Test-Path $PckFullPath) -or (Get-Item $PckFullPath).Length -le 0) {
    throw "Godot did not create a non-empty $PckFullPath. OTA publishing was stopped."
}

$Sha256 = (Get-FileHash -Path $PckFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
$PckUrl = "https://github.com/$Repo/releases/latest/download/$PckName"
$Manifest = [ordered]@{
    version = $Version
    pck_url = $PckUrl
    sha256 = $Sha256
    notes = $Notes
}
$Manifest | ConvertTo-Json | Set-Content -Path (Join-Path $OutDir $ManifestName) -Encoding utf8

Write-Host "==> Publishing GitHub Release $Tag to $Repo..."
gh release create $Tag `
    $PckFullPath `
    (Join-Path $OutDir $ManifestName) `
    --repo $Repo `
    --title "OTA $Version" `
    --notes $Notes
if ($LASTEXITCODE -ne 0) {
    throw "gh release create failed (exit code $LASTEXITCODE)."
}

Write-Host ""
Write-Host "==> Done. Players' OtaUpdater.gd should point MANIFEST_URL at:"
Write-Host "    https://github.com/$Repo/releases/latest/download/$ManifestName"
Write-Host ""
Write-Host "(Only set that once - it never changes between versions, just run"
Write-Host "this script again for the next update.)"
