@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_notification_plugin_v6.ps1"
if errorlevel 1 (
    echo.
    echo Notification Scheduler v6.0 installation failed.
    pause
    exit /b 1
)
echo.
echo Notification Scheduler v6.0 is ready. You can export SpotRush from Godot now.
pause
endlocal
