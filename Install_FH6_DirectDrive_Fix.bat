@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path '%~dp0' -Recurse | Unblock-File -ErrorAction SilentlyContinue; & '%~dp0Install_FH6_DirectDrive_Fix.ps1'"
echo.
pause
