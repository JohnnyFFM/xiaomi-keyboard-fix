#!/system/bin/sh
# kbd_leds.sh - Caps Lock LED + keyboard backlight for the Xiaomi Pad 7 / 7 Pro
# keyboard on crDroid. Caps follows the Caps key; backlight is adjusted with a
# modifier combo (default Ctrl+Alt+4 brighter / Ctrl+Alt+3 dimmer) because the
# keyboard has no dedicated backlight key. The keyboard holds each LED once set.
DEV=/dev/nanodev0
DIR=/data/adb/kbd
LOG=$DIR/leds.log

# Caps Lock feature command (newer MCUs: 0x2e, on=fd off=fc; 2022-MCU: 26/01/00)
CAPS_CMD=2e
CAPS_ON=fd
CAPS_OFF=fc

# Backlight (cmd 0x23, level 0-100). Adjusted by <modifiers>+<down/up key>.
# Default combo: Ctrl+Alt+3 = dimmer, Ctrl+Alt+4 = brighter (0 = off).
BL_CMD=23
BL_MAX=100
BL_STEP=20
BL_DEFAULT=60
BL_NEED_CTRL=1          # require Ctrl in the combo (1/0)
BL_NEED_ALT=1           # require Alt  in the combo (1/0)
BL_KEY_UP=KEY_4         # brighter
BL_KEY_DOWN=KEY_3       # dimmer

mkdir -p "$DIR"
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done
sleep 4

up() { cut -d' ' -f1 /proc/uptime; }
logline() { echo "$(up)  $*" >> "$LOG"; }
sum_hex() { s=0; for h in "$@"; do s=$((s + 0x$h)); done; printf '%02x' $((s & 255)); }
send_frame() {   # build a 66-byte frame and write it straight to the device
    fmt=""; fn=0
    for h in "$@"; do fmt="$fmt\\$(printf '%03o' $((0x$h)))"; fn=$((fn+1)); done
    [ $fn -gt 66 ] && { logline "frame >66 bytes, skipped"; return 1; }
    while [ $fn -lt 66 ]; do fmt="$fmt\\000"; fn=$((fn+1)); done
    printf "$fmt" > "$DEV" 2>/dev/null
}
send_feature() {   # $1=cmd hex, $2=value hex
    body="4e 31 80 38 $1 01 $2"
    send_frame 32 00 $body $(sum_hex $body)
}

logline "## kbd_leds start (caps $CAPS_CMD; backlight combo ctrl=$BL_NEED_CTRL alt=$BL_NEED_ALT $BL_KEY_DOWN/$BL_KEY_UP)"

CAPSDEV=$(getevent -pl 2>/dev/null | awk '/^add device /{d=$4} /LED_CAPSL/{print d; exit}')
logline "caps/keys EVDEV=${CAPSDEV:-<none>}"

bl_send() { send_feature "$BL_CMD" "$(printf '%02x' $1)"; logline "backlight=$1"; }

(
  cs=off; ctrl=0; alt=0; bl=0; bllast=$BL_DEFAULT
  getevent -lq $CAPSDEV 2>/dev/null | while read a b c rest; do
      case "$b" in
          KEY_LEFTCTRL|KEY_RIGHTCTRL) [ "$c" = "DOWN" ] && ctrl=1; [ "$c" = "UP" ] && ctrl=0 ;;
          KEY_LEFTALT|KEY_RIGHTALT)   [ "$c" = "DOWN" ] && alt=1;  [ "$c" = "UP" ] && alt=0 ;;
          KEY_CAPSLOCK)
              [ "$c" = "DOWN" ] && {
                  if [ "$cs" = "on" ]; then cs=off; send_feature "$CAPS_CMD" "$CAPS_OFF"; logline "caps OFF"
                  else cs=on; send_feature "$CAPS_CMD" "$CAPS_ON"; logline "caps ON"; fi; } ;;
          LED_CAPSL)
              case "$c" in
                  00000000|0) [ "$cs" != "off" ] && { cs=off; send_feature "$CAPS_CMD" "$CAPS_OFF"; logline "caps OFF (sync)"; } ;;
                  *)          [ "$cs" != "on"  ] && { cs=on;  send_feature "$CAPS_CMD" "$CAPS_ON";  logline "caps ON (sync)"; } ;;
              esac ;;
      esac
      # backlight combo (modifiers must be held)
      if [ "$c" = "DOWN" ] && { [ "$BL_NEED_CTRL" = 0 ] || [ "$ctrl" = 1 ]; } && { [ "$BL_NEED_ALT" = 0 ] || [ "$alt" = 1 ]; }; then
          case "$b" in
              "$BL_KEY_UP")   bl=$((bl + BL_STEP)); [ $bl -gt $BL_MAX ] && bl=$BL_MAX; bllast=$bl; bl_send $bl ;;
              "$BL_KEY_DOWN") bl=$((bl - BL_STEP)); [ $bl -lt 0 ] && bl=0; [ $bl -gt 0 ] && bllast=$bl; bl_send $bl ;;
          esac
      fi
  done
) &
wait
