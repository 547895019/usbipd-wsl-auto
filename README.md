# usbipd-wsl-auto

把白名单里的 USB 串口自动共享，并挂进 WSL2。插上就挂，不用每次手动 `usbipd bind` / `usbipd attach`；支持多只相同 VID:PID 的串口。

[English README](README.en.md) · [贡献指南](CONTRIBUTING.md) · [MIT License](LICENSE)

## 特性

- 按 `InstanceId` 和 `BusId` 区分设备，多只相同型号的串口也能分别挂载。
- 安装器自动选择默认 WSL 发行版，也可用 `-Distro` 指定。
- 新设备自动共享；已插入设备自动挂载，断开后自动恢复。
- 使用当前用户的登录计划任务，后台运行不需要保持终端窗口。
- 可编辑白名单、临时暂停、查看日志，以及完整卸载本包添加的策略。

`usbipd attach --auto-attach` 适合跟随单只设备；本项目通过轮询 `usbipd state` 处理整个白名单，因此不依赖硬件 ID 唯一。

## 依赖

- Windows 10/11、Windows PowerShell 5.1
- [usbipd-win](https://github.com/dorssel/usbipd-win) 5.x，默认安装到 `C:\Program Files\usbipd-win\usbipd.exe`
- 已安装并至少启动过一次的 WSL2 发行版

只有安装、卸载需要管理员权限。登录后的监视任务用当前用户权限运行。

## 安装

在 GitHub 选择 **Code → Download ZIP**，或克隆仓库：

```powershell
git clone https://github.com/547895019/usbipd-wsl-auto.git
cd usbipd-wsl-auto
```

把整个文件夹放在本地磁盘，例如：

```text
C:\Users\Public\usbipd-wsl-auto
```

安装后不要移动或删除该目录，计划任务会从这里运行脚本。

正式安装包包含以下五个文件。`config.json` 由安装器生成，不需要手工创建。

正式安装包只有以下五个文件。`config.json` 由安装器生成，不需要手工创建。

| 文件 | 用途 |
| --- | --- |
| `allowlist.ps1` | 自动挂载的 VID:PID 白名单 |
| `usbipd-wsl-auto.ps1` | 登录后常驻的监视脚本 |
| `install.ps1` | 选择 WSL、添加策略并注册登录任务 |
| `uninstall.ps1` | 删除任务和本安装器记录的策略 |
| `README.md` | 本文档 |

在该目录打开 PowerShell，执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

脚本会自动选择 Windows 的默认 WSL 发行版，并在需要时请求 UAC 提权。也可明确指定：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Distro Ubuntu-24.04
```

发行版名可在 `wsl -l -q` 里查看。装好后确认任务：

```powershell
Get-ScheduledTask usbipd-wsl-auto
Get-ScheduledTaskInfo usbipd-wsl-auto
```

`State` 应为 `Running`，`LastTaskResult` 为 `267009` 表示任务正在运行。任务在每次当前用户登录时启动，异常退出时最多重试 10 次，每次间隔 1 分钟。

安装器会：

1. 给白名单里的 VID:PID 添加 `AutoBind` 策略，让新插入的设备自动共享。
2. 把选用的发行版和策略 GUID 写进 `config.json`，供监视器和卸载脚本使用。
3. 注册并立即启动当前用户的 `usbipd-wsl-auto` 计划任务。

重复安装不会叠加同一白名单的策略。卸载会按 GUID 清理，不使用 `policy remove --all`，不会影响其他策略。

## 验证

```powershell
usbipd list
Get-Content $env:LOCALAPPDATA\usbipd-wsl-auto\attach.log -Tail 20
```

白名单设备应为 `Attached`。例如两只 CH343 都是 `1a86:55d3`，会分别按 BUSID 挂载，不会只挂一只。

在 WSL 中确认：

```bash
lsusb
ls -l /dev/ttyUSB* /dev/ttyACM*
```

CH340/CH341 通常显示为 `/dev/ttyUSB*`；CH343、CP210x 也可能由 `cdc_acm` 驱动，显示为 `/dev/ttyACM*`。当前用户需要访问串口时，将用户加入 `dialout` 组后重新登录 WSL：

```bash
sudo usermod -aG dialout $USER
```

## 白名单

默认包括：

| VID:PID | 芯片 |
| --- | --- |
| `1a86:55d3` | 沁恒 CH343 |
| `1a86:55d4` | 沁恒 CH9102 |
| `1a86:7523` | 沁恒 CH340 |
| `1a86:5523` | 沁恒 CH341 |
| `10c4:ea60` | Silicon Labs CP210x / CP2102N |
| `0403:6001` | FTDI FT232 |
| `0403:6010` | FTDI FT2232 |
| `0403:6011` | FTDI FT4232 |
| `0403:6014` | FTDI FT232H |
| `0403:6015` | FTDI FT231X |
| `2207:0006` | Rockchip ADB(安卓调试桥接口) |
| `303a:1001` | ESP32 USB-Serial-JTAG(串口 + JTAG 调试) |

查看设备的 VID:PID：

```powershell
usbipd list
usbipd state
```

**整只 USB 设备会被转发。** 挂进 WSL 后，它在 Windows 上的 COM 口、JTAG、U 盘等都会离开 Windows。Rockchip ADB (`2207:0006`) 和 ESP32 USB-Serial-JTAG (`303a:1001`) 挂进 WSL 期间，Windows 侧的 adb 和 esptool 看不到这块板。ESP32 的 `303a:1002`(串口+U 盘)、ATLink 等复合设备和 Rockchip 刷机模式 `2207:350a`(Rockusb) 没有默认加入，以保证 Windows 的烧录工具可用。确有需要时再加入 `allowlist.ps1`，然后重新运行安装器。

## 日志、暂停和手动操作

日志位于：

```text
%LOCALAPPDATA%\usbipd-wsl-auto\attach.log
```

每 2 秒轮询一次。连接中断会等待 8 秒再重挂；失败后等待 20 秒重试。WSL 重启后设备掉回 `Shared` 时也会自动恢复，不要求拔插。

临时停止所有自动挂载：

```powershell
New-Item -ItemType File -Path .\PAUSE -Force
Remove-Item .\PAUSE
```

把单只设备交回 Windows：

```powershell
usbipd detach --busid 1-3
```

将 `1-3` 换成实际 BUSID。监视器可能在约 8 秒后重新挂回；需要长期使用 Windows 时，先建 `PAUSE` 文件，或卸载。

`Device in error state` 会自动按 `unbind` → `bind --force` → `attach` 处理。

## 卸载

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

卸载会停止并删除计划任务和监视进程，删除本安装器记录的 `AutoBind` 策略，以及配置和状态文件。日志保留供排查，脚本目录也不会自行删除。

**已经挂进 WSL 的设备不会被卸载脚本拆掉。** 要交回 Windows，请手动执行 `usbipd detach --busid <BUSID>`。
