#!/system/bin/sh
# kbdauth.sh - Magisk service.d boot launcher for the keyboard MiAuth bridge.
# Starts the MiDevAuth HAL daemon (vendor servicemanager) and the handshake bridge.
DIR=/data/adb/kbdauth
KLOG=/data/adb/kbd/svc.log
mkdir -p /data/adb/kbd
echo "=== $(date) boot launcher ===" >> "$KLOG"
# wait for full boot and the keyboard device node
i=0; while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 120 ]; do sleep 2; i=$((i+1)); done
i=0; while [ ! -e /dev/nanodev0 ] && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
sleep 3
# one HAL daemon
kill -9 $(pidof midevauthd) 2>/dev/null
LD_LIBRARY_PATH="$DIR":/vendor/lib64:/system/lib64 setsid "$DIR/midevauthd" >"$DIR/d.log" 2>&1 </dev/null &
# wait until it registers with the vendor servicemanager
i=0; while [ $i -lt 30 ]; do vndservice list 2>/dev/null | grep -q midevauth && break; sleep 1; i=$((i+1)); done
echo "$(date) daemon pid=$(pidof midevauthd) vnd=$(vndservice list 2>/dev/null | grep -c midevauth)" >> "$KLOG"
# handshake bridge (tokenhelper path via HELPER env)
export HELPER="$DIR/tokenhelper"
setsid "$DIR/kbd_auth.sh" >"$DIR/run.log" 2>&1 </dev/null &
echo "$(date) bridge launched" >> "$KLOG"
