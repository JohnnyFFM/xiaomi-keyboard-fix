#!/system/bin/sh
# kbd_leds.sh - Caps Lock LED + keyboard backlight for the Xiaomi Pad 7 / 7 Pro
# keyboard on crDroid. The keyboard holds an LED once set, so these are one-shot
# commands triggered by the relevant keys (the key press is the activity that
# makes the keyboard apply the change).
DEV=/dev/nanodev0
DIR=/data/adb/kbd
LOG=$DIR/leds.log

# Caps Lock feature command. Newer MCUs (Pad 7/7Pro): cmd 0x2e, on=0xfd off=0xfc.
# "2022-MCU" units instead use: CAPS_CMD=26 CAPS_ON=01 CAPS_OFF=00
CAPS_CMD=2e
CAPS_ON=fd
CAPS_OFF=fc
# Backlight (cmd 0x23, level 0-100). Driven by the keyboard's own backlight keys
# (KBDILLUMUP/DOWN/TOGGLE), exactly like stock.
BL_CMD=23
BL_MAX=100
BL_STEP=20          # % change per Up/Down press
BL_DEFAULT=60       # level a Toggle/Up restores to from off

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

logline "## kbd_leds start (caps $CAPS_CMD; backlight $BL_CMD step=$BL_STEP)"

# find the keyboard nodes by capability: LED_CAPSL (caps) and KBDILLUM (backlight keys)
CAPSDEV=$(getevent -pl 2>/dev/null | awk '/^add device /{d=$4} /LED_CAPSL/{print d; exit}')
ILLUMDEV=$(getevent -pl 2>/dev/null | awk '/^add device /{d=$4} /KEY_KBDILLUMUP/{print d; exit}')
logline "caps EVDEV=${CAPSDEV:-<none>}  illum EVDEV=${ILLUMDEV:-<none>}"

bl_send() { send_feature "$BL_CMD" "$(printf '%02x' $1)"; logline "backlight=$1"; }

# --- Caps Lock: act on KEY_CAPSLOCK press (Android emits LED_CAPSL only on the
#     NEXT key; the press itself is the activity that refreshes the LED).
(
  cs=off
  getevent -lq $CAPSDEV 2>/dev/null | while read line; do
      case "$line" in
          *KEY_CAPSLOCK*DOWN*)
              if [ "$cs" = "on" ]; then cs=off; send_feature "$CAPS_CMD" "$CAPS_OFF"; logline "caps OFF"
              else cs=on; send_feature "$CAPS_CMD" "$CAPS_ON"; logline "caps ON"; fi ;;
          *LED_CAPSL*)
              val=$(echo "$line" | awk '{print $NF}')
              case "$val" in
                  00000000|0) [ "$cs" != "off" ] && { cs=off; send_feature "$CAPS_CMD" "$CAPS_OFF"; logline "caps OFF (sync)"; } ;;
                  *)          [ "$cs" != "on"  ] && { cs=on;  send_feature "$CAPS_CMD" "$CAPS_ON";  logline "caps ON (sync)"; } ;;
              esac ;;
      esac
  done
) &

# --- Backlight: respond to the keyboard's backlight keys (Up/Down/Toggle). ---
(
  bl=0; bllast=$BL_DEFAULT
  [ -n "$ILLUMDEV" ] || { logline "backlight: no KBDILLUM device; backlight keys disabled"; exit 0; }
  getevent -lq $ILLUMDEV 2>/dev/null | while read line; do
      case "$line" in
          *KEY_KBDILLUMUP*DOWN*)
              bl=$((bl + BL_STEP)); [ $bl -gt $BL_MAX ] && bl=$BL_MAX; bllast=$bl; bl_send $bl ;;
          *KEY_KBDILLUMDOWN*DOWN*)
              bl=$((bl - BL_STEP)); [ $bl -lt 0 ] && bl=0; [ $bl -gt 0 ] && bllast=$bl; bl_send $bl ;;
          *KEY_KBDILLUMTOGGLE*DOWN*)
              if [ $bl -gt 0 ]; then bllast=$bl; bl=0; else bl=$bllast; fi; bl_send $bl ;;
      esac
  done
) &

wait
