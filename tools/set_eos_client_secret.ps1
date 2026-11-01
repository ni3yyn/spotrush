$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$secureSecret = Read-Host 'Paste your EOS Client Secret (hidden; rotate the previously exposed value before public release)' -AsSecureString
$secureEncryptionKey = Read-Host 'Paste the EOS 64-character hexadecimal Encryption Key (input is hidden)' -AsSecureString
$secretPointer = [IntPtr]::Zero
$keyPointer = [IntPtr]::Zero
try {
    $secretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSecret)
    $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureEncryptionKey)
    $plainSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer)
    $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)

    if ([string]::IsNullOrWhiteSpace($plainSecret)) {
        throw 'The EOS Client Secret cannot be empty.'
    }
    if ($plainKey -notmatch '^[0-9a-fA-F]{64}$') {
        throw 'The EOS Encryption Key must be exactly 64 hexadecimal characters.'
    }

    $env:EOS_CLIENT_SECRET = $plainSecret
    $env:EOS_ENCRYPTION_KEY = $plainKey
    Push-Location $projectRoot
    try {
        python tools/generate_eos_local_config.py
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not create the local EOS configuration.'
        }
    }
    finally {
        Pop-Location
        Remove-Item Env:EOS_CLIENT_SECRET -ErrorAction SilentlyContinue
        Remove-Item Env:EOS_ENCRYPTION_KEY -ErrorAction SilentlyContinue
    }
}
finally {
    if ($secretPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
    }
    if ($keyPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
    }
    $plainSecret = $null
    $plainKey = $null
    $secureSecret.Dispose()
    $secureEncryptionKey.Dispose()
}
