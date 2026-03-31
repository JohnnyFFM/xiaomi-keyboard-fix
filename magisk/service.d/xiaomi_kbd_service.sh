#!/system/bin/sh
# Magisk service.d script for xiaomi_kbd_daemon
# Place in /data/adb/service.d/ with chmod 755

DAEMON="/data/adb/service.d/xiaomi_kbd_daemon"
LOG="/data/local/tmp/xiaomi_kbd_daemon.log"

# Wait until Android has fully booted
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
done
sleep 2

# Kill any existing instance
pkill -f xiaomi_kbd_daemon 2>/dev/null
sleep 1

echo "$(date): Starting xiaomi_kbd_daemon" >> "$LOG"

# Start daemon in its own session so it survives script exit
setsid $DAEMON 2>> "$LOG" &

echo "$(date): Daemon launched" >> "$LOG"
