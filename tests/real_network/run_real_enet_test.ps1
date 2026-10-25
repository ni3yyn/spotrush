$godotExe = 'C:\Users\HP\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe'
$cwd = 'C:\Users\HP\Desktop\New folder\spotrush'

Write-Host "=================================================="
Write-Host " REAL TWO-PROCESS ENET MULTIPLAYER INTEGRATION TEST"
Write-Host "=================================================="

Write-Host "`n[1/3] Launching Independent Host Process on port 7025..."
$hostProcess = Start-Process -FilePath $godotExe -ArgumentList "--headless -s res://tests/real_network/host_process.gd" -WorkingDirectory $cwd -PassThru -NoNewWindow -RedirectStandardOutput "$cwd\tests\real_network\host.log" -RedirectStandardError "$cwd\tests\real_network\host_err.log"

Start-Sleep -Milliseconds 1200

Write-Host "[2/3] Launching Independent Client Process connecting to 127.0.0.1:7025..."
$clientProcess = Start-Process -FilePath $godotExe -ArgumentList "--headless -s res://tests/real_network/client_process.gd" -WorkingDirectory $cwd -PassThru -NoNewWindow -RedirectStandardOutput "$cwd\tests\real_network\client.log" -RedirectStandardError "$cwd\tests\real_network\client_err.log"

Write-Host "[3/3] Waiting for real network handshake, challenge exchange, and scoring..."
$clientProcess.WaitForExit(9000)
$hostProcess.WaitForExit(9000)
$clientProcess.Refresh()
$hostProcess.Refresh()

$hostLogContent = if (Test-Path "$cwd\tests\real_network\host.log") { Get-Content "$cwd\tests\real_network\host.log" -Raw } else { "" }
$clientLogContent = if (Test-Path "$cwd\tests\real_network\client.log") { Get-Content "$cwd\tests\real_network\client.log" -Raw } else { "" }

Write-Host "`n--- HOST PROCESS LOG ---"
Write-Host $hostLogContent

Write-Host "`n--- CLIENT PROCESS LOG ---"
Write-Host $clientLogContent

$hostPassed = $hostLogContent.Contains(">> REAL TWO-PROCESS TEST PASSED ON HOST! <<")
$clientPassed = $clientLogContent.Contains(">> REAL TWO-PROCESS TEST PASSED ON CLIENT! <<")

Write-Host "`n--------------------------------------------------"
Write-Host "Host Verified Passed: $hostPassed"
Write-Host "Client Verified Passed: $clientPassed"
Write-Host "--------------------------------------------------"

if ($hostPassed -and $clientPassed) {
    Write-Host "`n>>> REAL TWO-PROCESS ENET TEST: PASSED! <<<`n"
    exit 0
} else {
    Write-Host "`n>>> REAL TWO-PROCESS ENET TEST: FAILED! <<<`n"
    exit 1
}
