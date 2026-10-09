#!/system/bin/sh
# kbd_leds.sh - Caps Lock LED (and optional keyboard backlight) for the Xiaomi
# Pad 7 / 7 Pro keyboard on crDroid. The keyboard HOLDS the LED once set, so we
# simply mirror the host's state - no re-assert, toggle, or timer.
DEV=/dev/nanodev0
DIR=/data/adb/kbd
LOG=$DIR/leds.log

# Caps Lock feature command. Newer MCUs (Pad 7/7Pro): cmd 0x2e, on=0xfd off=0xfc.
# "2022-MCU" units instead use: CAPS_CMD=26 CAPS_ON=01 CAPS_OFF=00
CAPS_CMD=2e
CAPS_ON=fd
CAPS_OFF=fc
# Backlight: mirror the pad screen brightness onto the keyboard backlight.
BACKLIGHT=1
BL_CMD=23
KBD_BL_MAX=100          # keyboard backlight is a 0-100 scale (per stock); tune if needed
BL_POLL=2

mkdir -p "$DIR"
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done
sleep 4

up() { cut -d' ' -f1 /proc/uptime; }
logline() { echo "$(up)  $*" >> "$LOG"; }
sum_hex() { s=0; for h in "$@"; do s=$((s + 0x$h)); done; printf '%02x' $((s & 255)); }
send_frame() {   # build a 66-byte frame and write it straight to the device (no temp file)
    fmt=""; fn=0
    for h in "$@"; do fmt="$fmt\\$(printf '%03o' $((0x$h)))"; fn=$((fn+1)); done
    [ $fn -gt 66 ] && { logline "frame >66 bytes, skipped"; return 1; }
    while [ $fn -lt 66 ]; do fmt="$fmt\\000"; fn=$((fn+1)); done
    printf "$fmt" > "$DEV" 2>/dev/null
}
send_feature() {   # $1=cmd hex, $2=value hex  -> short-data feature frame
    body="4e 31 80 38 $1 01 $2"
    send_frame 32 00 $body $(sum_hex $body)
}

logline "## kbd_leds start (caps cmd=$CAPS_CMD on=$CAPS_ON off=$CAPS_OFF; backlight=$BACKLIGHT)"

# the keyboard reporting LED_CAPSL is the one to watch
EVDEV=$(getevent -pl 2>/dev/null | awk '/^add device /{dev=$4} /LED_CAPSL/{print dev; exit}')
logline "caps: EVDEV=${EVDEV:-<none>}"

# Caps Lock: mirror Android's state (one command per change; the keyboard holds it)
(
  cs=off
  getevent -lq $EVDEV 2>/dev/null | while read line; do
      case "$line" in
          *KEY_CAPSLOCK*DOWN*)
              # act on the key press itself (Android emits LED_CAPSL only on the NEXT key)
              if [ "$cs" = "on" ]; then cs=off; send_feature "$CAPS_CMD" "$CAPS_OFF"; logline "caps OFF"
              else cs=on; send_feature "$CAPS_CMD" "$CAPS_ON"; logline "caps ON"; fi ;;
          *LED_CAPSL*)
              # authoritative state - correct drift only (usually already matches)
              val=$(echo "$line" | awk '{print $NF}')
              case "$val" in
                  00000000|0) [ "$cs" != "off" ] && { cs=off; send_feature "$CAPS_CMD" "$CAPS_OFF"; logline "caps OFF (sync)"; } ;;
                  *)          [ "$cs" != "on"  ] && { cs=on;  send_feature "$CAPS_CMD" "$CAPS_ON";  logline "caps ON (sync)"; } ;;
              esac ;;
      esac
  done
) &

# Backlight: mirror pad screen brightness onto the keyboard backlight (on change)
if [ "$BACKLIGHT" = "1" ]; then
  BLDIR=$(ls -d /sys/class/backlight/* 2>/dev/null | head -1)
  if [ -n "$BLDIR" ] && [ -r "$BLDIR/brightness" ]; then
    PMAX=$(cat "$BLDIR/max_brightness" 2>/dev/null); { [ -z "$PMAX" ] || [ "$PMAX" = "0" ]; } && PMAX=2047
    logline "backlight: src=$BLDIR max=$PMAX kbd_max=$KBD_BL_MAX"
    last=-1
    while true; do
      p=$(cat "$BLDIR/brightness" 2>/dev/null)
      case "$p" in ''|*[!0-9]*) sleep "$BL_POLL"; continue;; esac
      lvl=$(( p * KBD_BL_MAX / PMAX )); [ $lvl -gt $KBD_BL_MAX ] && lvl=$KBD_BL_MAX
      if [ "$lvl" != "$last" ]; then
        send_feature "$BL_CMD" "$(printf '%02x' $lvl)"; logline "backlight pad=$p kbd=$lvl"; last=$lvl
      fi
      sleep "$BL_POLL"
    done
  else
    logline "backlight: no /sys/class/backlight source; disabled"; wait
  fi
else
  wait
fi
