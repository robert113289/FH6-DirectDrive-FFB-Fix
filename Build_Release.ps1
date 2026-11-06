$ErrorActionPreference = 'Stop'
$repoDir = $PSScriptRoot

Write-Host "Building Prebuilt_Drop_In/wheeltunablesettingspc.zip and FH6_Universal_DirectDrive_FFB_Fix.zip from config/..." -ForegroundColor Cyan

# 1. Apply the latest config/ to the live game folder (-Force) and copy the resulting wheeltunablesettingspc.zip into Prebuilt_Drop_In/
& "$repoDir\Install_FH6_DirectDrive_Fix.ps1" -AutoMode -Force
Copy-Item "C:\XboxGames\Forza Horizon 6\Content\media\wheeltunablesettingspc.zip" "$repoDir\Prebuilt_Drop_In\wheeltunablesettingspc.zip" -Force

# 2. Rebuild FH6_Universal_DirectDrive_FFB_Fix.zip
$zipOut = "$repoDir\FH6_Universal_DirectDrive_FFB_Fix.zip"
if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
Compress-Archive -Path "$repoDir\config", "$repoDir\Prebuilt_Drop_In", "$repoDir\Install_FH6_DirectDrive_Fix.bat", "$repoDir\Install_FH6_DirectDrive_Fix.ps1", "$repoDir\Uninstall_Restore_Stock.bat", "$repoDir\README.md", "$repoDir\LICENSE", "$repoDir\FH6_InGame_Sliders.png" -DestinationPath $zipOut -Force

Write-Host "Successfully rebuilt release artifacts!" -ForegroundColor Green
