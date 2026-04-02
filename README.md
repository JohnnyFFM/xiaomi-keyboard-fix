# Xiaomi Pro Keyboard Fix for Custom ROMs

Makes the Xiaomi Pro Keyboard work on custom ROMs where Android disables it at boot.

## Problem

The Xiaomi Pro Keyboard connects via pogo pins and is detected by the kernel, but Android's InputReader marks it as `Enabled: false`. Keystrokes are silently discarded.

You can verify this with:

```bash
adb shell "dumpsys input" | grep -A4 "Xiaomi Keyboard"
```

If it shows `Enabled: false`, this fix will help.

## Solution

A HID unbind/rebind after boot forces Android to re-evaluate the device and enable it. No daemon, no binary, just a shell script.

## Install

### Prerequisites

- Magisk (for root and `service.d` boot scripts)

### 1. Install the boot script

```bash
adb push magisk/service.d/xiaomi_kbd_service.sh /data/local/tmp/
adb shell "su -c 'cp /data/local/tmp/xiaomi_kbd_service.sh /data/adb/service.d/'"
adb shell "su -c 'chmod 755 /data/adb/service.d/xiaomi_kbd_service.sh'"
```

### 2. Install the IDC config

Fixes arrow keys being rotated in landscape mode:

```bash
adb push magisk/keyboard_fix /data/local/tmp/keyboard_fix
adb shell "su -c 'mkdir -p /data/adb/modules/keyboard_fix'"
adb shell "su -c 'cp -r /data/local/tmp/keyboard_fix/* /data/adb/modules/keyboard_fix/'"
```

### 3. Reboot

```bash
adb reboot
```

## Verify

```bash
# Check the keyboard is enabled
adb shell "dumpsys input" | grep -A4 "Xiaomi Keyboard"

# Check the boot script ran
adb logcat -s xiaomi_kbd
```

## How It Works

The Xiaomi Pro Keyboard registers as a HID device via the Nanosic controller chip over the pogo-pin interface. On boot, the kernel loads `nanosic_driver` and `xiaomi_keyboard_driver`, which register the keyboard as `/dev/input/eventX`.

However, Android's InputReader disables the device at boot. The exact cause is unclear — it could be a timing issue during boot, a missing software component, or an Android policy decision. A HID unbind/rebind forces the device to re-register, and Android then enables it.

The boot script waits for `sys.boot_completed` before performing the rebind to ensure Android's input system is ready.

The IDC file sets `keyboard.orientationAware = 0` to prevent arrow keys from rotating with the screen orientation in landscape mode.

## Repository Structure

```
├── magisk/
│   ├── service.d/
│   │   └── xiaomi_kbd_service.sh    # Boot script (the actual fix)
│   └── keyboard_fix/                # Magisk module for IDC config
│       ├── module.prop
│       └── system/usr/idc/
│           └── Vendor_15d9_Product_00a3.idc
├── LICENSE
└── README.md
```

## Tested On

- **Device:** Xiaomi Pad 7 Pro
- **ROM:** crDroid (Android 16)
- **Keyboard:** Xiaomi Pro Keyboard (vendor=0x15d9, product=0x00a3)

May also work on other Xiaomi tablets with pogo-pin keyboards.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Keyboard not working after reboot | Check `adb logcat -s xiaomi_kbd` for errors |
| `Xiaomi keyboard HID device not found` | Keyboard not attached or different vendor/product IDs |
| Arrow keys rotated in landscape | Install the IDC Magisk module (step 2) |

## License

MIT
