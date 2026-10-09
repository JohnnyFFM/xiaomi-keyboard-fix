#!/system/bin/sh
# kbd_leds.sh - Caps Lock LED + (optional) keyboard backlight for the Xiaomi
# Pad 7 / 7 Pro keyboard on crDroid. Mirrors host state to the keyboard via the
# same short feature command stock uses. Runs alongside the auth bridge.
#
# EXPERIMENTAL (dev branch): verify CAPS_CMD/values for your MCU and tune
# KBD_BL_MAX on your unit. Caps Lock is the tested-priority feature.
DEV=/dev/nanodev0
DIR=/data/adb/kbd
LOG=$DIR/leds.log

# ---- config -------------------------------------------------------------
# Caps Lock feature command. Newer MCUs (Pad 7/7Pro): cmd 0x2e, on=0xfd off=0xfc.
# "2022-MCU" units instead use: CAPS_CMD=26 CAPS_ON=01 CAPS_OFF=00
CAPS_CMD=2e
CAPS_ON=fd
CAPS_OFF=fc
# Backlight: mirror the pad screen brightness onto the keyboard backlight.
BACKLIGHT=1
BL_CMD=23
KBD_BL_MAX=255
BL_POLL=2
# ------------------------------------------------------------------------

mkdir -p "$DIR"
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done
sleep 4

up() { cut -d' ' -f1 /proc/uptime; }
logline() { echo "$(up)  $*" >> "$LOG"; }

send_frame() {   # args: hex bytes; pads to 66 and writes one frame
    fmt=""; fn=0
    for h in "$@"; do fmt="$fmt\\$(printf '%03o' $((0x$h)))"; fn=$((fn+1)); done
    while [ $fn -lt 66 ]; do fmt="$fmt\\000"; fn=$((fn+1)); done
    printf "$fmt" > "$DIR/hframe.bin"
    [ "$(wc -c < "$DIR/hframe.bin")" != "66" ] && { logline "frame size bad, not sent"; return 1; }
    cat "$DIR/hframe.bin" > "$DEV" 2>/dev/null
}

logline() { echo "$(up)  $*" >> "$LOG"; }

send_frame() {   # args: hex bytes; pads to 66 and writes one frame
    fmt=""; fn=0
    for h in "$@"; do fmt="$fmt\\$(printf '%03o' $((0x$h)))"; fn=$((fn+1)); done
    while [ $fn -lt 66 ]; do fmt="$fmt\\000"; fn=$((fn+1)); done
    printf "$fmt" > "$DIR/hframe.bin"
    [ "$(wc -c < "$DIR/hframe.bin")" != "66" ] && { logline "frame size bad, not sent"; return 1; }
    cat "$DIR/hframe.bin" > "$DEV" 2>/dev/null
}

send_frame() {   # args: hex bytes; pads to 66 and writes one frame
    fmt=""; fn=0
    for h in "$@"; do fmt="$fmt\\$(printf '%03o' $((0x$h)))"; fn=$((fn+1)); done
    while [ $fn -lt 66 ]; do fmt="$fmt\\000"; fn=$((fn+1)); done
    printf "$fmt" > "$DIR/hframe.bin"
    [ "$(wc -c < "$DIR/hframe.bin")" != "66" ] && { logline "frame size bad, not sent"; return 1; }
    cat "$DIR/hframe.bin" > "$DEV" 2>/dev/null
}

sum_hex() { s=0; for h in "$@"; do s=$((s + 0x$h)); done; printf '%02x' $((s & 255)); }

send_auth_start() {
    body="4f 31 80 38 31 06 4d 49 41 55 54 48"
    send_frame 32 00 $body $(sum_hex $body)
}

send_feature() {   # $1=cmd hex, $2=value hex  -> short-data feature frame
    body="4e 31 80 38 $1 01 $2"
    send_frame 32 00 $body $(sum_hex $body)
}

logline "## kbd_leds start (caps cmd=$CAPS_CMD on=$CAPS_ON off=$CAPS_OFF; backlight=$BACKLIGHT)"

# find the keyboard input event device (for LED_CAPSL); empty => getevent watches all
EVDEV=$(awk 'BEGIN{RS="";FS="\n"}
  /15[dD]9|[Kk]eyboard/ { for(i=1;i<=NF;i++) if($i ~ /Handlers=/){ if(match($i,/event[0-9]+/)) { print "/dev/input/" substr($i,RSTART,RLENGTH); exit } } }' \
  /proc/bus/input/devices 2>/dev/null)
logline "caps: EVDEV=${EVDEV:-<all>}"

# Caps Lock watcher: react to EV_LED/LED_CAPSL the kernel emits on each toggle
(
  getevent -lq $EVDEV 2>/dev/null | while read line; do
      case "$line" in
          *LED_CAPSL*)
              val=$(echo "$line" | awk '{print $NF}')
              case "$val" in
                  00000000|0) send_feature "$CAPS_CMD" "$CAPS_OFF"; logline "caps OFF" ;;
                  *)          send_feature "$CAPS_CMD" "$CAPS_ON";  logline "caps ON"  ;;
              esac ;;
      esac
  done
) &

# Backlight mirror: keyboard backlight tracks pad screen brightness
if [ "$BACKLIGHT" = "1" ]; then
  BLDIR=$(ls -d /sys/class/backlight/* 2>/dev/null | head -1)
  if [ -n "$BLDIR" ] && [ -r "$BLDIR/brightness" ]; then
    PMAX=$(cat "$BLDIR/max_brightness" 2>/dev/null); { [ -z "$PMAX" ] || [ "$PMAX" = "0" ]; } && PMAX=2047
    logline "backlight: src=$BLDIR max=$PMAX kbd_max=$KBD_BL_MAX"
    last=-1
    while true; do
      p=$(cat "$BLDIR/brightness" 2>/dev/null)
      case "$p" in ''|*[!0-9]*) sleep "$BL_POLL"; continue;; esac
      lvl=$(( p * KBD_BL_MAX / PMAX ))
      [ $lvl -gt $KBD_BL_MAX ] && lvl=$KBD_BL_MAX
      if [ "$lvl" != "$last" ]; then
        send_feature "$BL_CMD" "$(printf '%02x' $lvl)"
        logline "backlight pad=$p kbd=$lvl"
        last=$lvl
      fi
      sleep "$BL_POLL"
    done
  else
    logline "backlight: no /sys/class/backlight source; disabled"; wait
  fi
else
  wait
fi
