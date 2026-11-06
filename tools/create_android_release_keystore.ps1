$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$keystorePath = Join-Path $repoRoot "spotrush-release.keystore"

if (Test-Path -LiteralPath $keystorePath) {
    throw "Keystore already exists at '$keystorePath'. Refusing to overwrite it."
}

if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
    throw "keytool was not found. Install/configure a JDK, then run this script again."
}

Write-Host "Creating the SpotRush upload keystore. Enter the password in the keytool prompt."
Write-Host "When asked for the key password, press Enter to use the same password."
Write-Host "Alias: spotrush"

keytool -genkeypair -v `
    -keystore $keystorePath `
    -alias spotrush `
    -keyalg RSA `
    -keysize 2048 `
    -validity 10000 `
    -dname "CN=SpotRush"

if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $keystorePath)) {
    throw "Keystore generation failed."
}

$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystorePath))
Set-Clipboard -Value $base64

Write-Host "Keystore created and its base64 value copied to the clipboard."
Write-Host "Create GitHub secret ANDROID_KEYSTORE_BASE64 by pasting the clipboard contents."
Write-Host "Create ANDROID_KEYSTORE_PASSWORD with the password you entered, and ANDROID_KEY_ALIAS with: spotrush"
Write-Host "Keep the keystore backed up securely; do not commit it or share the clipboard contents."
