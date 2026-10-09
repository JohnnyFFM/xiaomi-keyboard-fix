#!/system/bin/sh
# start.sh - run MiDevAuth HAL daemon + keyboard auth bridge (detached).
# Requires in the same dir: midevauthd, libmidevauth.so,
# vendor.xiaomi.hardware.aidl.midevauth-V1-ndk_platform.so, tokenhelper, kbd_auth.sh
HERE=$(dirname "$0"); cd "$HERE"
kill -9 $(pidof midevauthd) 2>/dev/null
LD_LIBRARY_PATH="$HERE":/vendor/lib64:/system/lib64 setsid ./midevauthd >"$HERE/d.log" 2>&1 </dev/null &
sleep 5
for p in $(ps -A 2>/dev/null | grep kbd_auth | awk '{print $2}'); do kill -9 "$p" 2>/dev/null; done
setsid ./kbd_auth.sh >"$HERE/run.log" 2>&1 </dev/null &
sleep 3
echo "midevauthd=$(pidof midevauthd) vndservice=$(vndservice list 2>/dev/null | grep -c midevauth)"
