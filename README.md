# Xiaomi Pogo Keyboard Daemon

A minimal userspace daemon that bridges the Xiaomi pogo-pin keyboard to Android's input stack on AOSP-based ROMs (crDroid, LineageOS, etc.).

## Problem

On AOSP-based ROMs, the Xiaomi Pad 7 Pro's pogo-pin keyboard (`vendor=0x15d9`, `product=0x00a3`) doesn't work out of the box:

- The kernel module `xiaomi_keyboard_driver` registers an input handler that intercepts keyboard events
- Without Xiaomi's proprietary userspace daemon, Android's InputReader disables the device (`Enabled: false`)
- The keyboard appears in `/proc/bus/input/devices` but produces no output

## Solution

This daemon:

1. Opens the physical keyboard device (`/dev/input/eventX`) — auto-detected by vendor/product ID
2. Creates a virtual device via `/dev/uinput` that mimics the keyboard
3. Forwards all raw `input_event` structs from the physical device to the virtual device
4. Runs as a persistent background service via Magisk's `service.d`
5. Survives keyboard dock/undock — rescans `/dev/input/` on reconnect

The daemon is layout-agnostic — it forwards raw keycodes without remapping. Keyboard layout (QWERTZ, QWERTY, etc.) is handled by Android's `.kcm`/`.kl` files separately.

## Repository Structure

```
├── xiaomi_kbd_daemon.c              # Daemon source (pure C)
├── Makefile                         # NDK cross-compilation
├── magisk/
│   ├── service.d/
│   │   └── xiaomi_kbd_service.sh    # Magisk boot service script
│   └── keyboard_fix/                # Magisk module for IDC config
│       ├── module.prop
│       └── system/usr/idc/
│           └── Vendor_15d9_Product_00a3.idc
```

## Build

### Prerequisites

- Ubuntu/Debian host
- Android NDK r27c (or later)

### Install NDK

```bash
sudo apt install wget unzip
cd ~
wget https://dl.google.com/android/repository/android-ndk-r27c-linux.zip
unzip android-ndk-r27c-linux.zip
```

### Compile

```bash
make
```

If your NDK is in a non-default location:

```bash
NDK_HOME=/path/to/ndk make
```

Output: `xiaomi_kbd_daemon` — a statically linked arm64 binary (~430 KB).

## Install

### 1. Push the daemon binary

```bash
adb push xiaomi_kbd_daemon /data/local/tmp/
adb shell "su -c 'cp /data/local/tmp/xiaomi_kbd_daemon /data/adb/service.d/'"
adb shell "su -c 'chmod 755 /data/adb/service.d/xiaomi_kbd_daemon'"
```

### 2. Install the boot service script

```bash
adb push magisk/service.d/xiaomi_kbd_service.sh /data/local/tmp/
adb shell "su -c 'cp /data/local/tmp/xiaomi_kbd_service.sh /data/adb/service.d/'"
adb shell "su -c 'chmod 755 /data/adb/service.d/xiaomi_kbd_service.sh'"
```

### 3. Install the Magisk IDC module

This module sets `keyboard.orientationAware = 0` so arrow keys don't rotate with the screen. Without it, arrow keys are swapped in landscape mode.

```bash
adb push magisk/keyboard_fix /data/local/tmp/keyboard_fix
adb shell "su -c 'mkdir -p /data/adb/modules/keyboard_fix'"
adb shell "su -c 'cp -r /data/local/tmp/keyboard_fix/* /data/adb/modules/keyboard_fix/'"
```

### 4. Reboot

```bash
adb reboot
```

### Quick Test (without reboot)

Run the daemon in foreground to test immediately:

```bash
adb push xiaomi_kbd_daemon /data/local/tmp/
adb shell "su -c '/data/local/tmp/xiaomi_kbd_daemon -f'"
```

Press `Ctrl+C` to stop.

## Verify

After reboot, check that everything is working:

```bash
# Daemon is running
adb shell "su -c 'ps -A | grep xiaomi_kbd'"

# Virtual device exists
adb shell "su -c 'cat /proc/bus/input/devices'" | grep -A5 "Pogo"

# Check the log
adb shell "su -c 'cat /data/local/tmp/xiaomi_kbd_daemon.log'"
```

## How It Works

```
┌─────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ Xiaomi Keyboard │     │ xiaomi_kbd_daemon │     │ Android          │
│ (pogo pins)     │────▶│                  │────▶│ InputReader      │
│                 │     │ read(event6)     │     │                  │
│ /dev/input/     │     │ write(uinput)    │     │ /dev/input/      │
│   event6        │     │                  │     │   event17        │
└─────────────────┘     └──────────────────┘     └──────────────────┘
     physical               EVIOCGRAB              virtual device
     device                 forwards all           seen by Android
                            events 1:1
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Daemon not starting | Check `cat /data/local/tmp/xiaomi_kbd_daemon.log` |
| Keyboard not detected | Verify with `cat /proc/bus/input/devices \| grep 15d9` |
| Arrow keys rotated in landscape | Install the IDC Magisk module (step 3) |
| Wrong characters | Set the correct keyboard language in Android Settings → System → Languages & Input |
| Daemon dies on undock | Expected — it auto-restarts when keyboard is re-docked |

## Tested On

- **Device:** Xiaomi Pad 7 Pro
- **ROM:** crDroid (AOSP-based)
- **Keyboard:** Xiaomi Pogo Pin Keyboard (vendor=0x15d9, product=0x00a3)

## License

MIT
