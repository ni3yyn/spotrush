$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$ArchivePath = Join-Path $env:TEMP 'NotificationSchedulerPlugin-Android-v6.0.zip'
$DownloadUrl = 'https://github.com/godot-mobile-plugins/godot-notification-scheduler/releases/download/v6.0/NotificationSchedulerPlugin-Android-v6.0.zip'
$ExpectedSha256 = '806c85eafe8f4c8aa4ee37e0ed1ab551e85db8755f8aeb1c6302092f809725a3'

Write-Host 'Downloading official Notification Scheduler v6.0 Android package...'
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ArchivePath

$ActualSha256 = (Get-FileHash -Path $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ActualSha256 -ne $ExpectedSha256) {
    throw "Notification Scheduler archive checksum mismatch. Expected $ExpectedSha256, got $ActualSha256."
}

# Remove stale native binaries from the old integration before installing v6.
$LegacyAars = @(
    (Join-Path $ProjectRoot 'addons/NotificationSchedulerPlugin/bin/debug/NotificationSchedulerPlugin-4.1-debug.aar'),
    (Join-Path $ProjectRoot 'addons/NotificationSchedulerPlugin/bin/release/NotificationSchedulerPlugin-4.1-release.aar')
)
foreach ($LegacyAar in $LegacyAars) {
    if (Test-Path $LegacyAar) { Remove-Item -Path $LegacyAar -Force }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$Zip = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
try {
    $Entries = @{
        'res/addons/NotificationSchedulerPlugin/bin/debug/NotificationSchedulerPlugin-debug.aar' = 'addons/NotificationSchedulerPlugin/bin/debug/NotificationSchedulerPlugin-debug.aar'
        'res/addons/NotificationSchedulerPlugin/bin/release/NotificationSchedulerPlugin-release.aar' = 'addons/NotificationSchedulerPlugin/bin/release/NotificationSchedulerPlugin-release.aar'
    }

    foreach ($EntryPath in $Entries.Keys) {
        $Entry = $Zip.GetEntry($EntryPath)
        if ($null -eq $Entry) {
            throw "The official v6.0 archive is missing expected entry: $EntryPath"
        }

        $Destination = Join-Path $ProjectRoot $Entries[$EntryPath]
        $DestinationDirectory = Split-Path -Parent $Destination
        New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $Destination, $true)
    }
}
finally {
    $Zip.Dispose()
}

# v6.0's default icon name is ic_default_notification. Copy SpotRush's
# monochrome notification artwork into the plugin's expected Android resources.
$AssetRoot = Join-Path $ProjectRoot 'assets/NotificationSchedulerPlugin/android'
foreach ($Density in @('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi')) {
    $Source = Join-Path $ProjectRoot "android_extras/res/drawable-$Density/ic_notification.png"
    $DestinationDirectory = Join-Path $AssetRoot "drawable-$Density"
    $Destination = Join-Path $DestinationDirectory 'ic_default_notification.png'
    if (-not (Test-Path $Source)) {
        throw "Missing SpotRush notification icon: $Source"
    }
    New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
    Copy-Item -Path $Source -Destination $Destination -Force
}

Write-Host 'Notification Scheduler v6.0 installed and checksum-verified.'
Write-Host 'You can now export the Android build from Godot.'
