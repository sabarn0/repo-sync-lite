@echo off
echo ======================================================
echo Unblocking all PowerShell scripts in repo-sync-lite...
echo ======================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path '%~dp0' -Recurse | Unblock-File"
echo Scripts unblocked successfully! You can now run .ps1 scripts directly.
echo.
pause
