@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0merge_changes.ps1" %*
