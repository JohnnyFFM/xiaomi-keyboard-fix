#!/system/bin/sh
# Connection-aware Xiaomi keyboard handling for crDroid on Xiaomi Pad 7 (muyu).
# Replacement for /data/adb/service.d/xiaomi_kbd_service.sh (chmod 755).
#
# Background:
#   The nanosic kernel driver registers a virtual HID "Xiaomi Keyboard"
#   (0006:15D9:00A3) at boot, whether or not the keyboard is attached.
#   XiaomiParts (KeyboardUtilsService) hides it by disabling that input
#   device once at boot and never re-enables it.  The old script blindly
#   rebound the HID after boot, which re-enables it for good and makes
#   Android think a hardware keyboard is always present, so the on-screen
#   keyboard is suppressed.
#
#   This version binds the HID only while the keyboard reports Connected=[1]
#   and unbinds it when detached, so the soft keyboard comes back.
#
# NOTE: verify the Connected field with the keyboard attached first:
#   adb shell su -c "cat /sys/class/nanodev/nanodev0/_version176x"
# Expected detached:  Connected=[0] Power=[0] HALL_N=[FAR]

HID="0006:15D9:00A3.0001"
DRV="/sys/bus/hid/drivers/hid-generic"
STATE="/sys/class/nanodev/nanodev0/_version176x"
TAG="xiaomi_kbd"
POLL=3

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done
sleep 2

last=""
while true; do
    if grep -q 'Connected=\[1\]' "$STATE" 2>/dev/null; then cur=1; else cur=0; fi
    if [ "$cur" != "$last" ]; then
        if [ "$cur" = "1" ]; then
            [ -e "$DRV/$HID" ] && echo "$HID" > "$DRV/unbind" && sleep 1
            echo "$HID" > "$DRV/bind" && log -t "$TAG" "keyboard attached: HID bound"
        else
            [ -e "$DRV/$HID" ] && echo "$HID" > "$DRV/unbind" && log -t "$TAG" "keyboard detached: HID unbound"
        fi
        last="$cur"
    fi
    sleep "$POLL"
done
