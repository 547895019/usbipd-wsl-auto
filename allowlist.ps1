# VID:PID values to share and attach into WSL.
# Whole-device attach: a match here leaves Windows (COM port, JTAG, mass storage)
# until the device is detached: esptool/JTAG in Windows cannot reach an attached
# ESP32, and Windows adb cannot reach an attached Rockchip board.
# ESP32 USB-serial+MSC 303a:1002 and Rockchip maskrom/rockusb 2207:350a are
# omitted on purpose so flashing and bootloader modes stay on the host side.
$Allow = @(
    '1a86:55d3'   # WCH CH343
    '1a86:55d4'   # WCH CH9102
    '1a86:7523'   # WCH CH340
    '1a86:5523'   # WCH CH341
    '10c4:ea60'   # Silicon Labs CP210x / CP2102N
    '0403:6001'   # FTDI FT232
    '0403:6010'   # FTDI FT2232
    '0403:6011'   # FTDI FT4232
    '0403:6014'   # FTDI FT232H
    '0403:6015'   # FTDI FT231X
    '2207:0006'   # Rockchip ADB (Android Debug Bridge interface)
    '303a:1001'   # ESP32 USB-Serial-JTAG (serial + JTAG debugging)
)
