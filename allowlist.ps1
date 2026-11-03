# VID:PID values to share and attach into WSL.
# Whole-device attach: a match here leaves Windows (COM port, JTAG, mass storage).
# ESP32 USB-Serial-JTAG 303a:1001 and USB-serial+MSC 303a:1002 are omitted on purpose.
# Rockchip maskrom/rockusb (2207:350a) is also omitted; bootloader mode stays in
# Windows so flashing tools and drivers keep working on the host side.
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
)
