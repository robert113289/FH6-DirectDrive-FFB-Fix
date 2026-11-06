@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install_FH6_DirectDrive_Fix.ps1" -Uninstall
echo.
pause
