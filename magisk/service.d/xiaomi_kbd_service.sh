#!/system/bin/sh
# Xiaomi Pro Keyboard fix for Custom ROMs
# Place in /data/adb/service.d/ with chmod 755
#
# Android's InputReader may disable the Xiaomi Pro Keyboard at boot
# (Enabled: false). A HID unbind/rebind after boot forces Android to
# re-evaluate and enable the device.
# Tested on Xiaomi Pad 7 Pro with crDroid. May also work on other
# Xiaomi tablets with pogo-pin keyboards.
#
# To check if your keyboard is affected:
#   adb shell "dumpsys input" | grep -A4 "Xiaomi Keyboard"
# If it shows "Enabled: false", this script will fix it.

HID_DRIVER="/sys/bus/hid/drivers/hid-generic"
TAG="xiaomi_kbd"

# Wait until Android has fully booted
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
done
sleep 2

# Find the Xiaomi keyboard HID device (vendor 15D9, product 00A3)
HID_DEVICE=""
for dev in "$HID_DRIVER"/0006:15D9:00A3.*; do
    if [ -e "$dev" ]; then
        HID_DEVICE="$(basename "$dev")"
        break
    fi
done

if [ -z "$HID_DEVICE" ]; then
    log -t "$TAG" "Xiaomi keyboard HID device not found"
    exit 1
fi

log -t "$TAG" "HID rebind $HID_DEVICE"

echo "$HID_DEVICE" > "$HID_DRIVER/unbind"
sleep 1
echo "$HID_DEVICE" > "$HID_DRIVER/bind"

log -t "$TAG" "Done"
