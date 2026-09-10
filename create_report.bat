@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0create_report.ps1" %*
