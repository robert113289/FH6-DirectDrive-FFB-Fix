# Forza Horizon 6 — Universal Direct Drive FFB Physics Fix

[![Download ZIP](https://img.shields.io/badge/%E2%AC%87%EF%B8%8F_Download_Installer-(.ZIP)-2ea44f?style=for-the-badge)](https://github.com/robert113289/FH6-DirectDrive-FFB-Fix/archive/refs/heads/main.zip)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: PC (Windows 10/11)](https://img.shields.io/badge/Platform-Windows%2010%2F11%20(Xbox%20App%20%26%20Steam)-0078D6.svg)](#5-how-to-install--uninstall)
[![Wheelbases: All Direct Drive](https://img.shields.io/badge/Wheelbases-Simucube%20%7C%20Fanatec%20%7C%20Simagic%20%7C%20Asetek%20%7C%20VRS%20%7C%20Moza-success.svg)](#1-why-direct-drive-wheels-feel-bad-out-of-the-box-in-forza-horizon-6)

Works for **all Direct Drive wheelbases** (Simucube 2 & 3, Fanatec DD1/DD2/CSL DD, Simagic, Asetek, VRS, Moza, Cammus, Conspit) and **multi-USB pedal setups** across **Xbox App / Microsoft Store** and **Steam**—with **no vJoy, HidHide, or EmuWheel required**.

> **Quick Install (No Git Required):**
> - **Option 1 (Download & Double-Click):** [**Click here to download the `.ZIP`**](https://github.com/robert113289/FH6-DirectDrive-FFB-Fix/archive/refs/heads/main.zip), extract the folder anywhere, and double-click **`Install_FH6_DirectDrive_Fix.bat`**.
> - **Option 2 (1-Line PowerShell Command):** Right-click your Windows Start button -> click **Terminal** (or **PowerShell**), paste this command, and press **Enter**:
>   ```powershell
>   irm https://raw.githubusercontent.com/robert113289/FH6-DirectDrive-FFB-Fix/main/Install_FH6_DirectDrive_Fix.ps1 | iex
>   ```

---

## 1. Why Direct Drive Wheels Feel Bad Out of the Box in Forza Horizon 6

Forza Horizon 6 uses a **two-layer Force Feedback system**:
1. **Hidden Physics Lookup Tables (`Content\media\wheeltunablesettingspc.zip`)**: 47 per-wheel `.ini` files that define 75 internal physics parameters (tire grip windows, low-load center boost, road spike clamps, internal tire-slip damping, and smoothing filters) **before** the game ever mixes the FFB signal.
2. **In-Game Sliders**: 10 simple multipliers at the end of the chain.

Because Forza mixes all physics forces into one combined USB torque command *before* sending it to your wheelbase, **neither the in-game sliders nor your wheelbase software (Simucube Tuner, Moza Pit House, Fanatec Control Panel, SimPro) can "un-bake" bad hidden `.ini` curves.**

Specifically, Direct Drive owners get hit by three issues inside Forza's `Content\media\` archives:
- **Bug #1 — Unrecognized Direct Drive Wheels (`Simucube 3`, `Simagic`, `Asetek`, `VRS`, newer `Moza`):**
  Because their USB IDs are missing from `wheeltunablesettingspc.zip`, Forza falls back to `ControllerFFB-0000000000.ini` (`Default`). `Default` has **no on-center low-load boost (`1.0`)**, **clips cornering grip early (`3.0`)**, adds **hidden internal tire-slip drag (`DampingAtMin/MaxSlip = 1`)**, and has **dull asphalt texture (`0.35`)** with a **high curb-spike ceiling (`0.50`)**.
- **Bug #2 — Legacy Direct Drive Profiles (`Simucube 2`, `Fanatec DD1 / DD2`):**
  Even worse, `ControllerFFB-0X16D00D60.ini` (`Simcube 2 Sport`) and `0x0eb70006.ini` / `0x0eb70007.ini` (`Fanatec DD1/DD2`) are the *only* files in the game where Playground Games enabled a heavy internal spring-damper filter (`SteerTorqueShouldSmooth = true`, `SpringK = 10000`, `SpringD = 3.0`), forced a `0.25` minimum damper floor, and locked caster flat at `9.0 -> 9.0`—making the wheel feel like **turning through molasses** the further you turn.
- **Bug #3 — No FFB on Multi-USB Rigs (`Content\media\inputmappingprofiles.zip`):**
  Stock custom wheel profiles (`CustomRawGameControllerProfile1..5.xml`) hardcode `FFBDeviceVidPid="1"`. If you have standalone USB pedals (e.g., Fanatec ClubSport V3, Heusinkveld, Simucube ActivePedal) or a separate shifter/handbrake plugged in, Forza frequently binds FFB to the wrong USB controller—resulting in **zero Force Feedback** unless you use third-party emulators like vJoy/EmuWheel.

---

## 2. What This Patch Does

Inside `wheeltunablesettingspc.zip`, Playground Games included a modern Direct Drive physics tune (`ControllerFFB-0X046DC272.ini`, engineered for an 11 Nm Direct Drive servo) that fixes every single one of the physics issues:

| Hidden `.ini` Parameter | Stock `Default` (`0000000000.ini`) | Stock `SC2 / DD1 / DD2` (`0X16D00D60.ini`) | **Patched Modern DD Curve** |
| :--- | :--- | :--- | :--- |
| **`SteerTorqueShouldSmooth`** *(Molasses Filter)* | `false` | `true` (`K=10000, D=3.0`) | **`false` (Clean, unfiltered)** |
| **`SteerTorqueMinNormLoadOut0`** *(On-Center Feel)* | `1.0` *(Vague center)* | `1.25` | **`1.25` (+25% center feel)** |
| **`SteerTorqueMin -> MaxLatFric`** *(Cornering Grip Window)* | `1.0 -> 3.0` *(Clips early)* | `2.0 -> 3.0` | **`1.5 -> 3.5` (Wider grip range)** |
| **`PneumaticCasterScaleMin -> Max`** *(Self-Aligning Pull)* | `8.5 -> 7.5` | `9.0 -> 9.0` *(Overpowering)* | **`7.0 -> 7.0` (Natural & smooth)** |
| **`DampingAtMin / MaxSlip`** *(Hidden Tire-Slip Drag)* | `1 / 1` *(Artificial drag)* | `1 / 1` | **`0 / 0` (Zero fake slip drag)** |
| **`RoadFeelScaleAsphalt`** *(Small Road Texture)* | `0.35` *(Muted)* | `0.50` | **`0.60` (Rich road surface detail)** |
| **`RoadFeelTorqueClamp`** *(Harsh Curb/Pothole Ceiling)* | `0.50` *(Harsh jolts)* | `0.35` | **`0.30` (Clamps violent spikes)** |

Running **`Install_FH6_DirectDrive_Fix.bat`** reads your local Forza archives, unpacks them in memory, injects the plain-text [`config/`](config) definitions, and repacks them:
1. **Upgrades `wheeltunablesettingspc.zip`:**
   - `ControllerFFB-0000000000.ini` (`Default` — automatically covers **any** unrecognized DD wheel: Simucube 3, Simagic, Asetek, VRS, Cammus, Moza, etc.)
   - `ControllerFFB-0X16D00D60.ini`, `0X16D00D5F.ini`, `0X16D00D65.ini`, `0X16D00D66.ini` (`Simucube 2 & Simucube 3`)
   - `ControllerFFB-0x0eb70006.ini` & `0x0eb70007.ini` (`Fanatec DD1 & DD2`)
2. **Fixes Multi-USB FFB Routing in `inputmappingprofiles.zip`:**
   - Auto-detects your connected Direct Drive wheelbase via Windows PnP (`Get-PnpDevice`) and sets `PrimaryDeviceVidPid`, `FFBDeviceVidPid`, and `WheelVidPid` in `CustomRawGameControllerProfile1..5.xml` / `CustomWheelMappingProfile1..5.xml` so Forza always sends FFB to your wheelbase, even with separate USB pedals connected.

*(Note: Forza uses a proprietary `.zip` format where every file's compressed payload must start on a 4096-byte page boundary with a custom `0x1123` extra-field header. Editing the `.zip` with 7-Zip or WinRAR breaks the archive—this script compiles a built-in C# packer on the fly that preserves Forza's exact 4096-byte page alignment).*

---

## 3. Recommended Wheelbase Software Settings (Any Brand)

To pair with this physics curve, set your wheelbase software (**Simucube Tuner**, **Moza Pit House**, **Fanatec Control Panel**, **Simagic SimPro**, **Asetek RaceHub**, **VRS**) as follows:

1. **Max Torque / Peak Force:** **`9.0 – 11.0 Nm`** (`10.5 Nm` sweet spot)
2. **Steering Range:** **`900°`** (`450°` per side)
3. **Damping:** **`5% – 6%` (CONSTANT / FLAT)**
   - **Important for Simucube 3 / Tuner users:** Default Simucube 3 profiles use an angle-ramping damping curve that ramps damping up between `5%` and `40%` steering angle—flatten that curve or use simple constant damping (`6%`), otherwise your wheelbase software itself will create a "turning through molasses" ramp-up! *(You can also search Simucube Tuner for **`Forza Horizon 6 - SC3 Pro (Clean & Responsive)`**).*
4. **Inertia:** **`0% / Off`**
5. **Friction:** **`2%`**
6. **Slew Rate / Effect Aggressiveness / Reconstruction:** Moderate (`~55%` Aggressiveness, `60%` Detail, `20%` HF Attenuation in Simucube Tuner; Filter `3–4` in TrueDrive/Fanatec)
7. **Synthetic UDP Telemetry Effects (Cornering Spring / Road Texture):** **`Off`** (let Forza's native physics FFB come through cleanly)

---

## 4. Recommended In-Game Settings (FH6 Advanced Controls)

![FH6 In-Game Advanced Controls Sliders](FH6_InGame_Sliders.png)

- **Steering Axis Deadzone Inside / Outside:** `0` / `100`
- **Vibration Scale:** `0.5`
- **Force Feedback Scale:** `1.0`
- **Center Spring Scale:** `0.1`
- **Wheel Damper Scale:** `0.0` *(let your wheelbase servo handle damping cleanly)*
- **Mechanical Trail Scale:** `0.80`
- **Force Feedback Minimum Force:** `1.1`
- **Force Feedback Load Sensitivity:** `1.0`
- **Road Feel Scale:** `0.8`
- **Off-Road Feel Scale:** `0.5`
- **Steering Sensitivity:** `0.5`

---

## 5. How to Install / Uninstall

This repository carries **zero proprietary game files**—it unpacks your own local `wheeltunablesettingspc.zip` and `inputmappingprofiles.zip` directly from your Forza Horizon 6 installation, injects the plain-text [`config/DirectDrive_Physics.ini`](config/DirectDrive_Physics.ini) and [`config/Target_Wheels.json`](config/Target_Wheels.json) settings in memory, and repacks the archives in place.

1. [**Click here to download the `.ZIP` directly**](https://github.com/robert113289/FH6-DirectDrive-FFB-Fix/archive/refs/heads/main.zip) and extract the folder anywhere on your PC.
2. Double-click **`Install_FH6_DirectDrive_Fix.bat`**:
   - Automatically finds your Forza Horizon 6 installation, saves a self-updating backup of your stock `.zip` files to `Documents\FH6_DirectDrive_FFB_Backup\`, and patches your archives.
   - Asks at the end: **`Would you like to automatically re-apply this patch whenever Forza Horizon 6 updates? (y/N)`** — if you type `y`, it copies the patcher to `Documents\FH6_DirectDrive_FFB_Backup\` (so you can safely delete your downloaded folder) and registers automatic checks for both **Xbox App** (instant update event hook) and **Steam** (login + daily check).
3. **To Revert to Stock (and remove the auto-update task):** Double-click **`Uninstall_Restore_Stock.bat`** (or run `irm https://raw.githubusercontent.com/robert113289/FH6-DirectDrive-FFB-Fix/main/Install_FH6_DirectDrive_Fix.ps1 | iex` with `-Uninstall`).

---

## 6. Customizing Physics or Adding Wheelbases (`config/`)

All physics parameters and USB hardware IDs are separated from the script in plain-text config files:
- **[`config/DirectDrive_Physics.ini`](config/DirectDrive_Physics.ini)**: Edit any of the 75 internal Forza FFB physics parameters in plain text and re-run `Install_FH6_DirectDrive_Fix.bat`.
- **[`config/Target_Wheels.json`](config/Target_Wheels.json)**: Add new wheelbase USB `VID/PID` entries for PnP auto-detection or explicit `.ini` injection without touching PowerShell or C# code.
