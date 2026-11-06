param(
    [switch]$Uninstall,
    [switch]$SkipAutoUpdateTask
)

$ErrorActionPreference = 'Stop'

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Forza Horizon 6 - Universal Direct Drive FFB Physics Patcher  " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

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

if (-not $mediaDir) {
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
    Write-Host "ERROR: Could not find wheeltunablesettingspc.zip. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "Found Forza Horizon 6 media directory:" -ForegroundColor Green
Write-Host "  $mediaDir"
Write-Host ""

$wtsPath = "$mediaDir\wheeltunablesettingspc.zip"
$impPath = "$mediaDir\inputmappingprofiles.zip"
$backupDir = "$env:USERPROFILE\Documents\FH6_DirectDrive_FFB_Backup"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

if ($Uninstall) {
    if (Test-Path "$backupDir\wheeltunablesettingspc_stock.zip") {
        Copy-Item "$backupDir\wheeltunablesettingspc_stock.zip" $wtsPath -Force
        Write-Host "Restored stock wheeltunablesettingspc.zip" -ForegroundColor Green
    }
    if (Test-Path "$backupDir\inputmappingprofiles_stock.zip") {
        Copy-Item "$backupDir\inputmappingprofiles_stock.zip" $impPath -Force
        Write-Host "Restored stock inputmappingprofiles.zip" -ForegroundColor Green
    }
    Unregister-ScheduledTask -TaskName "FH6_Universal_DD_AutoPatcher" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Uninstalled Universal Direct Drive FFB Patch and restored stock files." -ForegroundColor Cyan
    exit 0
}

# Save original stock backup if not already backed up
if (-not (Test-Path "$backupDir\wheeltunablesettingspc_stock.zip")) {
    Copy-Item $wtsPath "$backupDir\wheeltunablesettingspc_stock.zip" -Force
    Write-Host "Saved original stock backup to: $backupDir\wheeltunablesettingspc_stock.zip" -ForegroundColor Gray
}
if ((Test-Path $impPath) -and -not (Test-Path "$backupDir\inputmappingprofiles_stock.zip")) {
    Copy-Item $impPath "$backupDir\inputmappingprofiles_stock.zip" -Force
}

# 2. Compile Forza's 4096-byte page-aligned zip patcher (0x1123 extra field TLV)
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

# 3. Read wheeltunablesettingspc.zip and upgrade Default + Direct Drive profiles to the clean Modern DD physics table
$wtsEntries = [ForzaZipPatcher]::ReadForzaZip($wtsPath)
$logiEntry = $wtsEntries | Where-Object { $_.Name -ieq "ControllerFFB-0X046DC272.ini" } | Select-Object -First 1
$sc2Entry  = $wtsEntries | Where-Object { $_.Name -ieq "ControllerFFB-0X16D00D60.ini" } | Select-Object -First 1

if (-not $logiEntry) {
    Write-Host "ERROR: Could not find reference Direct Drive profile (0X046DC272.ini) in zip." -ForegroundColor Red
    exit 1
}

$baseDdTemplate = [System.Text.Encoding]::UTF8.GetString($logiEntry.UncompressedData)

# Helper to build a clean DD INI for any VendorProduct & FriendlyName (preserving positive DynFFBScale = 1)
function Build-CleanDdIni([string]$vendorProd, [string]$friendlyName, [string]$dynScale = "1") {
    $txt = $baseDdTemplate
    $txt = $txt -replace '(?m)^VendorProduct\s+.*$', "VendorProduct $vendorProd"
    $txt = $txt -replace '(?m)^FriendlyName\s+.*$', "FriendlyName $friendlyName"
    $txt = $txt -replace '(?m)^DynFFBScale\s+.*$', "DynFFBScale $dynScale"
    if ($vendorProd -eq "0000000000") {
        # Default fallback shouldn't override DegreesOfRotation
        $txt = $txt -replace '(?m)^DegreesOfRotation\s+.*\r?\n', ''
    }
    return $txt
}

# Upgrade Default (0000000000.ini) so ANY unrecognized Direct Drive wheel (Simucube 3, Simagic, Asetek, VRS, Moza, Cammus) gets the clean DD physics!
# Also upgrade Simucube 2 (0X16D00D60), Fanatec DD1/DD2 (0x0eb70006 / 0x0eb70007), and Moza (0X346E*) so none of them suffer from the molasses filter!
$upgradedTargets = @{
    "ControllerFFB-0000000000.ini" = @{ VP = "0000000000"; Name = "Default"; Scale = "1" }
    "ControllerFFB-0X16D00D60.ini" = @{ VP = "0x16D00D60"; Name = "Simcube 2 Sport"; Scale = "1" }
    "ControllerFFB-0x0eb70006.ini" = @{ VP = "0x0eb70006"; Name = "FanatecDD1"; Scale = "1" }
    "ControllerFFB-0x0eb70007.ini" = @{ VP = "0x0eb70007"; Name = "FanatecDD2"; Scale = "1" }
}

foreach ($e in $wtsEntries) {
    if ($upgradedTargets.ContainsKey($e.Name)) {
        $info = $upgradedTargets[$e.Name]
        $newTxt = Build-CleanDdIni $info.VP $info.Name $info.Scale
        [ForzaZipPatcher]::UpdateEntryText($e, $newTxt)
        Write-Host "  Upgraded $($e.Name) ($($info.Name)) -> Clean Modern DD Physics" -ForegroundColor Green
    }
}

# Also explicitly add Simucube 3 Pro (0X16D00D66), Simucube 3 Sport (0X16D00D65), and Simucube 2 Pro (0X16D00D5F) if not present
$explicitDdAdditions = @(
    @{ File = "ControllerFFB-0X16D00D5F.ini"; VP = "0x16D00D5F"; Name = "Simucube 2 Pro" },
    @{ File = "ControllerFFB-0X16D00D65.ini"; VP = "0x16D00D65"; Name = "Simucube 3 Sport" },
    @{ File = "ControllerFFB-0X16D00D66.ini"; VP = "0x16D00D66"; Name = "Simucube 3 Pro" }
)

foreach ($add in $explicitDdAdditions) {
    $existing = $wtsEntries | Where-Object { $_.Name -ieq $add.File } | Select-Object -First 1
    if ($existing) {
        [ForzaZipPatcher]::UpdateEntryText($existing, (Build-CleanDdIni $add.VP $add.Name "1"))
    } elseif ($sc2Entry) {
        $newEntry = New-Object ForzaZipPatcher+RawEntry
        $newEntry.Name = $add.File
        $newEntry.VerMade = $sc2Entry.VerMade
        $newEntry.VerNeed = $sc2Entry.VerNeed
        $newEntry.Flags = $sc2Entry.Flags
        $newEntry.Method = $sc2Entry.Method
        $newEntry.DosTime = $sc2Entry.DosTime
        [ForzaZipPatcher]::UpdateEntryText($newEntry, (Build-CleanDdIni $add.VP $add.Name "1"))
        $idx = $wtsEntries.IndexOf($sc2Entry)
        $wtsEntries.Insert($idx + 1, $newEntry)
        Write-Host "  Added $($add.File) ($($add.Name)) -> Clean Modern DD Physics" -ForegroundColor Green
    }
}

[ForzaZipPatcher]::WriteForzaZip($wtsPath, $wtsEntries)
Write-Host ""
Write-Host "Successfully patched wheeltunablesettingspc.zip (4096-byte page aligned)!" -ForegroundColor Cyan
Write-Host "Done! Restart Forza Horizon 6 to feel the updated Direct Drive physics." -ForegroundColor Green
