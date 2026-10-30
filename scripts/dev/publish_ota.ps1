#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Builds, versions, and publishes an OTA content pack for SpotRush to a
  GitHub Release on your existing repo. Windows/PowerShell twin of
  publish_ota.sh - same behavior, see that file's header for the full
  explanation of what a manifest.json is and why GitHub Releases.

.USAGE
  .\scripts\dev\publish_ota.ps1 1.0.1 "fix duel desync on reconnect"

.REQUIRES
  - Godot 4.7 editor on PATH as `godot`, or set $env:GODOT to its full .exe path
  - GitHub CLI (`gh`): winget install GitHub.cli, then `gh auth login`
  - Run from inside your repo checkout (so `gh` knows which repo), or set
    $env:GITHUB_REPO = "owner/repo" yourself
  - The "Android" export preset already set up in export_presets.cfg (it is)
#>

param(
	[Parameter(Mandatory = $true, Position = 0)]
	[string]$Version,

	[Parameter(Position = 1)]
	[string]$Notes = "OTA update $Version"
)

$ErrorActionPreference = "Stop"

$GodotBin = if ($env:GODOT) { $env:GODOT } else { "godot" }
$OutDir = "ota_builds"
$PckName = "content.pck"          # fixed name - keeps the "latest" URL stable
$ManifestName = "manifest.json"   # fixed name - same reason
$Tag = "ota-$Version"

$Repo = $env:GITHUB_REPO
if (-not $Repo) {
	$Repo = (gh repo view --json nameWithOwner -q .nameWithOwner) 2>$null
}
if (-not $Repo) {
	Write-Error "Could not determine the GitHub repo. Run this from inside your repo checkout, or set `$env:GITHUB_REPO = 'owner/repo'."
	exit 1
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Write-Host "==> Exporting content pack for version $Version..."
# Start-Process -Wait (not the & call operator) because on Windows the Godot
# editor binary is a GUI-subsystem executable: `&` can return to the script
# before Godot has actually finished writing the .pck, which is what caused
# the "content.pck not found" error on the previous run - the export was
# still in progress when the next line tried to hash the file.
$PckFullPath = Join-Path (Get-Location) "$OutDir\$PckName"
# Start-Process -ArgumentList does NOT auto-quote array elements containing
# spaces (unlike the & call operator) - with a path like "...\New
# folder\spotrush\..." that silently truncates the argument at the space.
# Building one pre-quoted command-line string instead avoids that.
$ArgumentLine = "--headless --export-pack Android `"$PckFullPath`""
$proc = Start-Process -FilePath $GodotBin `
	-ArgumentList $ArgumentLine `
	-NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) {
	Write-Error "Godot export failed (exit code $($proc.ExitCode))."
	exit 1
}
if (-not (Test-Path $PckFullPath)) {
	Write-Error "Godot reported success but $PckFullPath still doesn't exist - check the Godot output above for errors."
	exit 1
}

$Sha256 = (Get-FileHash -Path "$OutDir\$PckName" -Algorithm SHA256).Hash.ToLower()
$PckUrl = "https://github.com/$Repo/releases/latest/download/$PckName"

$Manifest = [ordered]@{
	version  = $Version
	pck_url  = $PckUrl
	sha256   = $Sha256
	notes    = $Notes
}
$Manifest | ConvertTo-Json | Set-Content -Path "$OutDir\$ManifestName" -Encoding utf8

Write-Host "==> Publishing GitHub Release $Tag to $Repo..."
gh release create $Tag `
	"$OutDir\$PckName" `
	"$OutDir\$ManifestName" `
	--repo $Repo `
	--title "OTA $Version" `
	--notes $Notes
if ($LASTEXITCODE -ne 0) {
	Write-Error "gh release create failed (exit code $LASTEXITCODE)."
	exit 1
}

Write-Host ""
Write-Host "==> Done. Players' OtaUpdater.gd should point MANIFEST_URL at:"
Write-Host "    https://github.com/$Repo/releases/latest/download/$ManifestName"
Write-Host ""
Write-Host "(Only set that once - it never changes between versions, just run"
Write-Host "this script again for the next update.)"