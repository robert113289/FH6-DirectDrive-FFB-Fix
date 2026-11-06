param(
    [switch]$Uninstall,
    [switch]$AutoMode,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$backupDir = "$env:USERPROFILE\Documents\FH6_DirectDrive_FFB_Backup"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

# Support both running from an extracted folder AND running via 1-line PowerShell (irm ... | iex)
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { $backupDir }
$configIniPath = Join-Path $scriptRoot "config\DirectDrive_Physics.ini"
$targetWheelsPath = Join-Path $scriptRoot "config\Target_Wheels.json"

if ((-not (Test-Path $configIniPath)) -or (-not (Test-Path $targetWheelsPath))) {
    $cfgDir = Join-Path $backupDir "config"
    New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
    $rawBase = "https://raw.githubusercontent.com/robert113289/FH6-DirectDrive-FFB-Fix/main"
    Invoke-WebRequest -UseBasicParsing -Uri "$rawBase/config/DirectDrive_Physics.ini" -OutFile "$cfgDir\DirectDrive_Physics.ini"
    Invoke-WebRequest -UseBasicParsing -Uri "$rawBase/config/Target_Wheels.json" -OutFile "$cfgDir\Target_Wheels.json"
    Invoke-WebRequest -UseBasicParsing -Uri "$rawBase/Install_FH6_DirectDrive_Fix.ps1" -OutFile "$backupDir\Install_FH6_DirectDrive_Fix.ps1"
    $scriptRoot = $backupDir
    $configIniPath = "$cfgDir\DirectDrive_Physics.ini"
    $targetWheelsPath = "$cfgDir\Target_Wheels.json"
}

if (-not $AutoMode) {
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  Forza Horizon 6 - Universal Direct Drive FFB Physics Patcher  " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
}

# 1. Auto-detect Forza Horizon 6 installation directory (MS Store / Xbox App or Steam)
$mediaDir = $null
$candidates = @(
    "C:\XboxGames\Forza Horizon 6\Content\media",
    "D:\XboxGames\Forza Horizon 6\Content\media",
    "E:\XboxGames\Forza Horizon 6\Content\media",
    "F:\XboxGames\Forza Horizon 6\Content\media",
    "C:\Program Files (x86)\Steam\steamapps\common\ForzaHorizon6\media",
    "D:\SteamLibrary\steamapps\common\ForzaHorizon6\media",
    "E:\SteamLibrary\steamapps\common\ForzaHorizon6\media"
)

try {
    $pkg = Get-AppxPackage -Name "Microsoft.ForteBaseGame*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg -and $pkg.InstallLocation) {
        $candidates = @("$($pkg.InstallLocation)\media") + $candidates
    }
} catch {}

foreach ($c in $candidates) {
    if ($c -and (Test-Path "$c\wheeltunablesettingspc.zip")) {
        $mediaDir = $c
        break
    }
}

if (-not $mediaDir -and (-not $AutoMode)) {
    Write-Host "Could not auto-detect Forza Horizon 6 folder. Please select the 'Forza Horizon 6' folder..." -ForegroundColor Yellow
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select your Forza Horizon 6 installation folder (or Content\media folder)"
    if ($dlg.ShowDialog() -eq 'OK') {
        if (Test-Path "$($dlg.SelectedPath)\wheeltunablesettingspc.zip") {
            $mediaDir = $dlg.SelectedPath
        } elseif (Test-Path "$($dlg.SelectedPath)\Content\media\wheeltunablesettingspc.zip") {
            $mediaDir = "$($dlg.SelectedPath)\Content\media"
        } elseif (Test-Path "$($dlg.SelectedPath)\media\wheeltunablesettingspc.zip") {
            $mediaDir = "$($dlg.SelectedPath)\media"
        }
    }
}

if (-not $mediaDir -or -not (Test-Path "$mediaDir\wheeltunablesettingspc.zip")) {
    if (-not $AutoMode) {
        Write-Host "ERROR: Could not find wheeltunablesettingspc.zip. Exiting." -ForegroundColor Red
    }
    return
}

$wtsPath = "$mediaDir\wheeltunablesettingspc.zip"
$impPath = "$mediaDir\inputmappingprofiles.zip"
$logPath = "$backupDir\patch_history.log"

if ($Uninstall) {
    $restoredAny = $false
    if (Test-Path "$backupDir\wheeltunablesettingspc_stock.zip") {
        Copy-Item "$backupDir\wheeltunablesettingspc_stock.zip" $wtsPath -Force
        Write-Host "Restored stock wheeltunablesettingspc.zip" -ForegroundColor Green
        $restoredAny = $true
    } else {
        Write-Host "WARNING: Backup file not found at $backupDir\wheeltunablesettingspc_stock.zip" -ForegroundColor Yellow
    }

    if ((Test-Path $impPath) -and (Test-Path "$backupDir\inputmappingprofiles_stock.zip")) {
        Copy-Item "$backupDir\inputmappingprofiles_stock.zip" $impPath -Force
        Write-Host "Restored stock inputmappingprofiles.zip" -ForegroundColor Green
        $restoredAny = $true
    }

    Unregister-ScheduledTask -TaskName "FH6_Universal_DD_AutoPatcher" -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "FH6_Simucube3_AutoPatcher" -Confirm:$false -ErrorAction SilentlyContinue

    $startupDir = [Environment]::GetFolderPath('Startup')
    Remove-Item "$startupDir\FH6_*_AutoPatcher.lnk" -Force -ErrorAction SilentlyContinue

    if ($restoredAny) {
        $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Add-Content -Path $logPath -Value "[$stamp] Uninstalled Universal DD FFB patch and restored stock archives."
        Write-Host "Successfully removed auto-update hooks and restored stock Forza Horizon 6 files." -ForegroundColor Cyan
    }
    return
}

# 2. Load config/Target_Wheels.json and config/DirectDrive_Physics.ini
$targetsConfig = Get-Content $targetWheelsPath -Raw | ConvertFrom-Json
$baseDdTemplate = Get-Content $configIniPath -Raw

# Auto-detect connected Direct Drive wheelbase USB VID/PID for inputmappingprofiles.zip (defaults to Simucube 3 Pro 0x16d00d66)
$activeWheel = $targetsConfig.default_input_mapping_wheel
try {
    $presentPnp = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Select-Object -ExpandProperty InstanceId
    foreach ($wb in $targetsConfig.auto_detect_wheelbases) {
        if ($presentPnp | Where-Object { $_ -match $wb.pnp_match }) {
            $activeWheel = $wb
            break
        }
    }
} catch {}

# 3. Fast check (~30ms): see if wheeltunablesettingspc.zip and inputmappingprofiles.zip are already patched
$wtsBytes = [System.IO.File]::ReadAllBytes($wtsPath)
$wtsText = [System.Text.Encoding]::ASCII.GetString($wtsBytes)
$hasSc3InWts = ([regex]::IsMatch($wtsText, "(?i)ControllerFFB-0X16D00D66\.ini"))
# When run interactively (-not $AutoMode), always apply the latest config; in -AutoMode, only patch when needed
$needsWtsPatch = $Force -or (-not $AutoMode) -or (-not $hasSc3InWts)

$needsImpPatch = $Force -or (-not $AutoMode)
$isImpStock = $false
if (Test-Path $impPath) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($impPath)
    try {
        $entry = $zip.GetEntry("CustomRawGameControllerProfile1.xml")
        if ($entry) {
            $sr = New-Object System.IO.StreamReader($entry.Open())
            $xmlTxt = $sr.ReadToEnd()
            $sr.Close()
            if ($xmlTxt.Contains('FFBDeviceVidPid="1"')) {
                $isImpStock = $true
            }
            if (-not $xmlTxt.Contains($activeWheel.vid_pid_hex)) {
                $needsImpPatch = $true
            }
        }
    } finally {
        $zip.Dispose()
    }
}

# Self-healing stock backups: if an archive in the game folder is currently unpatched stock (fresh install or just updated by Xbox/Steam),
# refresh the saved *_stock.zip backup BEFORE patching so Uninstall always restores the latest game version's stock archive!
if (-not $hasSc3InWts) {
    Copy-Item $wtsPath "$backupDir\wheeltunablesettingspc_stock.zip" -Force
}
if ($isImpStock) {
    Copy-Item $impPath "$backupDir\inputmappingprofiles_stock.zip" -Force
}

# Check if Playground Games officially added ControllerFFB-0X16D00D66.ini in a new Forza update!
if ($isImpStock -and $hasSc3InWts -and (-not $Force)) {
    $needsWtsPatch = $false
    $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $logPath -Value "[$stamp] DETECTED OFFICIAL SIMUCUBE 3 PRO SUPPORT IN FORZA UPDATE! Leaving official ControllerFFB-0X16D00D66.ini untouched so you can test it."
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        "The latest Forza Horizon 6 update officially added a Simucube 3 Pro profile (ControllerFFB-0X16D00D66.ini)!`n`nThe auto-patcher left Playground Games' new official SC3 profile untouched so you can try it out.",
        "Forza Horizon 6 - Official Simucube 3 Pro Support Added!",
        "OK",
        "Information"
    ) | Out-Null
}

if ((-not $needsWtsPatch) -and (-not $needsImpPatch)) {
    return
}

if (-not $AutoMode) {
    Write-Host "Found Forza Horizon 6 media directory: $mediaDir" -ForegroundColor Green
    Write-Host "Target Primary FFB Wheelbase: $($activeWheel.name) ($($activeWheel.vid_pid_hex))" -ForegroundColor Cyan
    Write-Host ""
}

# 4. Compile Forza's 4096-byte page-aligned zip patcher (0x1123 extra field TLV)
if (-not ('ForzaZipPatcher' -as [type])) {
Add-Type -ReferencedAssemblies "System.IO.Compression" -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;

public class ForzaZipPatcher {
    public class RawEntry {
        public string Name;
        public ushort VerMade;
        public ushort VerNeed;
        public ushort Flags;
        public ushort Method;
        public uint DosTime;
        public uint Crc32;
        public byte[] CompressedData;
        public byte[] UncompressedData;
    }

    private static uint ComputeCrc32(byte[] data) {
        uint crc = 0xFFFFFFFF;
        for (int i = 0; i < data.Length; i++) {
            crc ^= data[i];
            for (int j = 0; j < 8; j++) {
                if ((crc & 1) != 0) crc = (crc >> 1) ^ 0xEDB88320;
                else crc >>= 1;
            }
        }
        return ~crc;
    }

    public static byte[] DeflateRaw(byte[] raw) {
        using (var ms = new MemoryStream()) {
            using (var ds = new DeflateStream(ms, CompressionLevel.Optimal, true)) {
                ds.Write(raw, 0, raw.Length);
            }
            return ms.ToArray();
        }
    }

    public static List<RawEntry> ReadForzaZip(string path) {
        byte[] bytes = File.ReadAllBytes(path);
        int eocd = -1;
        for (int i = bytes.Length - 22; i >= 0; i--) {
            if (bytes[i] == 0x50 && bytes[i+1] == 0x4B && bytes[i+2] == 0x05 && bytes[i+3] == 0x06) {
                eocd = i;
                break;
            }
        }
        ushort count = BitConverter.ToUInt16(bytes, eocd + 10);
        uint cdOffset = BitConverter.ToUInt32(bytes, eocd + 16);
        int pos = (int)cdOffset;
        var list = new List<RawEntry>();
        for (int k = 0; k < count; k++) {
            ushort verMade = BitConverter.ToUInt16(bytes, pos + 4);
            ushort verNeed = BitConverter.ToUInt16(bytes, pos + 6);
            ushort flags = BitConverter.ToUInt16(bytes, pos + 8);
            ushort method = BitConverter.ToUInt16(bytes, pos + 10);
            uint dosTime = BitConverter.ToUInt32(bytes, pos + 12);
            uint crc = BitConverter.ToUInt32(bytes, pos + 16);
            uint compLen = BitConverter.ToUInt32(bytes, pos + 20);
            uint uncompLen = BitConverter.ToUInt32(bytes, pos + 24);
            ushort nameLen = BitConverter.ToUInt16(bytes, pos + 28);
            ushort extraLen = BitConverter.ToUInt16(bytes, pos + 30);
            ushort commentLen = BitConverter.ToUInt16(bytes, pos + 32);
            uint localHeaderOffset = BitConverter.ToUInt32(bytes, pos + 42);
            string name = Encoding.ASCII.GetString(bytes, pos + 46, nameLen);

            ushort localNameLen = BitConverter.ToUInt16(bytes, (int)localHeaderOffset + 26);
            ushort localExtraLen = BitConverter.ToUInt16(bytes, (int)localHeaderOffset + 28);
            int dataStart = (int)localHeaderOffset + 30 + localNameLen + localExtraLen;

            byte[] compData = new byte[compLen];
            Array.Copy(bytes, dataStart, compData, 0, (int)compLen);

            byte[] uncompData;
            using (var msIn = new MemoryStream(compData))
            using (var ds = new DeflateStream(msIn, CompressionMode.Decompress))
            using (var msOut = new MemoryStream()) {
                ds.CopyTo(msOut);
                uncompData = msOut.ToArray();
            }

            list.Add(new RawEntry {
                Name = name,
                VerMade = verMade,
                VerNeed = verNeed,
                Flags = flags,
                Method = method,
                DosTime = dosTime,
                Crc32 = crc,
                CompressedData = compData,
                UncompressedData = uncompData
            });

            pos += 46 + nameLen + extraLen + commentLen;
        }
        return list;
    }

    public static void UpdateEntryText(RawEntry entry, string newText) {
        byte[] raw = Encoding.UTF8.GetBytes(newText);
        entry.UncompressedData = raw;
        entry.Crc32 = ComputeCrc32(raw);
        entry.CompressedData = DeflateRaw(raw);
    }

    public static void WriteForzaZip(string outPath, List<RawEntry> entries) {
        using (var ms = new MemoryStream())
        using (var bw = new BinaryWriter(ms)) {
            var localOffsets = new List<uint>();
            var dataOffsets = new List<uint>();

            foreach (var e in entries) {
                uint localHeaderOffset = (uint)ms.Position;
                localOffsets.Add(localHeaderOffset);

                byte[] nameBytes = Encoding.ASCII.GetBytes(e.Name);
                uint minEnd = localHeaderOffset + 30 + (uint)nameBytes.Length + 4;
                uint alignedDataStart = ((minEnd + 4095) / 4096) * 4096;
                ushort extraLen = (ushort)(alignedDataStart - (localHeaderOffset + 30 + (uint)nameBytes.Length));
                dataOffsets.Add(alignedDataStart);

                bw.Write((uint)0x04034B50);
                bw.Write(e.VerNeed);
                bw.Write(e.Flags);
                bw.Write(e.Method);
                bw.Write(e.DosTime);
                bw.Write(e.Crc32);
                bw.Write((uint)e.CompressedData.Length);
                bw.Write((uint)e.UncompressedData.Length);
                bw.Write((ushort)nameBytes.Length);
                bw.Write(extraLen);
                bw.Write(nameBytes);

                bw.Write((ushort)0x1123);
                bw.Write((ushort)(extraLen - 4));
                bw.Write(new byte[extraLen - 4]);

                bw.Write(e.CompressedData);
            }

            uint cdStart = (uint)ms.Position;
            for (int i = 0; i < entries.Count; i++) {
                var e = entries[i];
                byte[] nameBytes = Encoding.ASCII.GetBytes(e.Name);
                bw.Write((uint)0x02014B50);
                bw.Write(e.VerMade);
                bw.Write(e.VerNeed);
                bw.Write(e.Flags);
                bw.Write(e.Method);
                bw.Write(e.DosTime);
                bw.Write(e.Crc32);
                bw.Write((uint)e.CompressedData.Length);
                bw.Write((uint)e.UncompressedData.Length);
                bw.Write((ushort)nameBytes.Length);
                bw.Write((ushort)8);
                bw.Write((ushort)0);
                bw.Write((ushort)0);
                bw.Write((ushort)0);
                bw.Write((uint)0);
                bw.Write(localOffsets[i]);
                bw.Write(nameBytes);
                bw.Write((ushort)0x1123);
                bw.Write((ushort)4);
                bw.Write(dataOffsets[i]);
            }
            uint cdEnd = (uint)ms.Position;
            uint cdSize = cdEnd - cdStart;

            bw.Write((uint)0x06054B50);
            bw.Write((ushort)0);
            bw.Write((ushort)0);
            bw.Write((ushort)entries.Count);
            bw.Write((ushort)entries.Count);
            bw.Write(cdSize);
            bw.Write(cdStart);
            bw.Write((ushort)0);

            bw.Flush();
            File.WriteAllBytes(outPath, ms.ToArray());
        }
    }
}
"@
}

function Build-CleanDdIni([string]$vendorProd, [string]$friendlyName, [string]$dynScale = "1") {
    $txt = $baseDdTemplate
    $txt = $txt -replace '(?m)^VendorProduct\s+.*$', "VendorProduct $vendorProd"
    $txt = $txt -replace '(?m)^FriendlyName\s+.*$', "FriendlyName $friendlyName"
    $txt = $txt -replace '(?m)^DynFFBScale\s+.*$', "DynFFBScale $dynScale"
    $txt = ($txt -replace "`r?`n", "`r`n").TrimEnd("`r", "`n")
    return $txt
}

# 5. Patch inputmappingprofiles.zip (ensures multi-USB rigs like Simucube 3 + Fanatec Pedals route FFB to the wheelbase)
if ($needsImpPatch -and (Test-Path $impPath)) {
    $impEntries = [ForzaZipPatcher]::ReadForzaZip("$backupDir\inputmappingprofiles_stock.zip")
    foreach ($e in $impEntries) {
        if ($e.Name -match "^CustomRawGameControllerProfile[1-5]\.xml$") {
            $txt = [System.Text.Encoding]::UTF8.GetString($e.UncompressedData)
            $txt = $txt -replace 'PrimaryDeviceVidPid="[^"]+"', "PrimaryDeviceVidPid=`"$($activeWheel.vid_pid_hex)`""
            $txt = $txt -replace 'FFBDeviceVidPid="[^"]+"', "FFBDeviceVidPid=`"$($activeWheel.vid_pid_hex)`""
            [ForzaZipPatcher]::UpdateEntryText($e, $txt)
        }
        elseif ($e.Name -match "^CustomWheelMappingProfile[1-5]\.xml$") {
            $txt = [System.Text.Encoding]::UTF8.GetString($e.UncompressedData)
            $txt = $txt -replace 'WheelVidPid="[^"]+"', "WheelVidPid=`"$($activeWheel.vid_pid_dec)`""
            [ForzaZipPatcher]::UpdateEntryText($e, $txt)
        }
    }
    [ForzaZipPatcher]::WriteForzaZip($impPath, $impEntries)
    if (-not $AutoMode) {
        Write-Host "  Patched inputmappingprofiles.zip -> FFBDeviceVidPid=$($activeWheel.vid_pid_hex)" -ForegroundColor Green
    }
}

# 6. Patch wheeltunablesettingspc.zip from clean stock backup, injecting only the active wheelbase INI in strict hex order
if ($needsWtsPatch) {
    $wtsEntries = [ForzaZipPatcher]::ReadForzaZip("$backupDir\wheeltunablesettingspc_stock.zip")
    $sc2Entry = $wtsEntries | Where-Object { $_.Name -ieq "ControllerFFB-0X16D00D60.ini" } | Select-Object -First 1

    $newTxt = Build-CleanDdIni $activeWheel.vendor_product $activeWheel.name "1"
    $existing = $wtsEntries | Where-Object { $_.Name -ieq $activeWheel.ini_file } | Select-Object -First 1

    if ($existing) {
        [ForzaZipPatcher]::UpdateEntryText($existing, $newTxt)
        if (-not $AutoMode) {
            Write-Host "  Upgraded $($existing.Name) ($($activeWheel.name)) -> Clean Modern DD Physics" -ForegroundColor Green
        }
    } elseif ($sc2Entry) {
        $newEntry = New-Object ForzaZipPatcher+RawEntry
        $newEntry.Name = $activeWheel.ini_file
        $newEntry.VerMade = $sc2Entry.VerMade
        $newEntry.VerNeed = $sc2Entry.VerNeed
        $newEntry.Flags = $sc2Entry.Flags
        $newEntry.Method = $sc2Entry.Method
        $newEntry.DosTime = $sc2Entry.DosTime
        [ForzaZipPatcher]::UpdateEntryText($newEntry, $newTxt)
        $idx = $wtsEntries.IndexOf($sc2Entry)
        $wtsEntries.Insert($idx + 1, $newEntry)
        if (-not $AutoMode) {
            Write-Host "  Injected $($activeWheel.ini_file) ($($activeWheel.name)) -> Clean Modern DD Physics" -ForegroundColor Green
        }
    }

    [ForzaZipPatcher]::WriteForzaZip($wtsPath, $wtsEntries)
}

$stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
Add-Content -Path $logPath -Value "[$stamp] Applied Universal DD FFB patch (WTS=$needsWtsPatch, IMP=$needsImpPatch, Wheel=$($activeWheel.name))"

if ($AutoMode) {
    return
}

Write-Host ""
Write-Host "Successfully patched Forza Horizon 6 archives (4096-byte page aligned)!" -ForegroundColor Cyan
Write-Host ""

# 7. Optional prompt to enable automatic re-patching after Forza Horizon 6 updates (Xbox App & Steam)
$ans = Read-Host "Would you like to automatically re-apply this patch whenever Forza Horizon 6 updates? (y/N)"
if ($ans -match "^[Yy]") {
    # Persist script and config/ into Documents\FH6_DirectDrive_FFB_Backup so user can safely delete their Downloads folder
    $savedScript = "$backupDir\Install_FH6_DirectDrive_Fix.ps1"
    if ($scriptRoot -ne $backupDir) {
        Copy-Item (Join-Path $scriptRoot "Install_FH6_DirectDrive_Fix.ps1") $savedScript -Force
        Copy-Item (Join-Path $scriptRoot "config") "$backupDir\config" -Recurse -Force
    }

    $taskName = "FH6_Universal_DD_AutoPatcher"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$savedScript`" -AutoMode"
    $CIMTriggerClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
    $triggerAppX = New-CimInstance -CimClass $CIMTriggerClass -ClientOnly
    $triggerAppX.Subscription = @"
<QueryList><Query Id="0" Path="Microsoft-Windows-AppXDeploymentServer/Operational"><Select Path="Microsoft-Windows-AppXDeploymentServer/Operational">*[System[Provider[@Name='Microsoft-Windows-AppXDeployment-Server'] and (EventID=400 or EventID=613)]]</Select></Query></QueryList>
"@
    $triggerAppX.Enabled = $true
    $triggerTime = New-ScheduledTaskTrigger -Daily -At "12:00PM"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($triggerAppX, $triggerTime) -Settings $settings -Description "Automatically re-applies Universal Direct Drive FFB physics & input mapping patch after Forza Horizon 6 game updates." -Force | Out-Null

    # Also add a silent Windows Login check in Startup folder so Steam updates are caught automatically at login too
    $startupDir = [Environment]::GetFolderPath('Startup')
    $wsh = New-Object -ComObject WScript.Shell
    $lnk = $wsh.CreateShortcut("$startupDir\FH6_Universal_DD_AutoPatcher.lnk")
    $lnk.TargetPath = "powershell.exe"
    $lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$savedScript`" -AutoMode"
    $lnk.WindowStyle = 7
    $lnk.Save()

    Write-Host "Enabled automatic update protection for Xbox App & Steam!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done! Restart Forza Horizon 6 to feel the updated Direct Drive physics." -ForegroundColor Green
