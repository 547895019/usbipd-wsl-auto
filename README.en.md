# usbipd-wsl-auto

Automatically share and attach allowlisted USB serial adapters to WSL2. Supports multiple adapters with the same VID:PID, automatic recovery after disconnection, and a login-time background watcher.

[中文说明](README.md)

## Requirements

- Windows 10/11 and Windows PowerShell 5.1
- [usbipd-win](https://github.com/dorssel/usbipd-win) 5.x in its default installation directory
- A WSL2 distribution that has been installed and started at least once

## Install

Download and extract the source archive, open PowerShell in the extracted directory, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

The installer detects the default WSL distribution, requests elevation when needed, adds AutoBind policies for the allowlist, and starts a per-user login task. To select a distribution explicitly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Distro Ubuntu-24.04
```

Keep the extracted folder in place: the scheduled task runs the scripts from that directory.

## Verify

```powershell
usbipd list
Get-ScheduledTask usbipd-wsl-auto
Get-Content $env:LOCALAPPDATA\usbipd-wsl-auto\attach.log -Tail 20
```

Allowlisted devices should show `Attached`. In WSL, run `adb devices` for Rockchip boards in ADB mode (`2207:0006`), check Espressif chips under `/dev/ttyACM*` via their USB-Serial-JTAG port (`303a:1001`), and:

```bash
lsusb
ls -l /dev/ttyUSB* /dev/ttyACM*
```

## Configure and pause

Edit `allowlist.ps1` to change the VID:PID list, then rerun the installer. Create an empty `PAUSE` file beside the scripts to suspend automatic attachment; delete it to resume.

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

The uninstaller removes the scheduled task, watcher, policies recorded by the installer, and generated configuration. It deliberately leaves already-attached devices attached. Use `usbipd detach --busid <BUSID>` to return a device to Windows.

## Important

USB/IP forwards the **entire USB device**, not only its COM port. Its Windows COM port, JTAG interface, mass storage, and other functions become unavailable in Windows while attached — for example, Windows-side `adb` no longer sees a Rockchip board once `2207:0006` is attached, and Windows-side esptool/JTAG cannot reach an ESP32 whose `303a:1001` port is attached. Review the allowlist before installation. The ESP32 USB-serial+MSC device `303a:1002`, ATLink composites, and Rockchip maskrom `2207:350a` (Rockusb, needed by host-side flashing tools) are not included by default.

## License

[MIT](LICENSE)
