#!/system/bin/sh
# Permanently disable Xiaomi's /odm/bin/toucheventcheck on crDroid.
#
# It is NOT a touch driver — the real touch HAL is the separate, healthy
# `touchfeature-service`. toucheventcheck is a MiSight *telemetry* daemon
# (libmisight.so / MiSight::sendEvent) that watches the input/touch nodes and
# reports anomalies to Xiaomi's cloud. On a custom ROM that telemetry is both
# unwanted and harmful: the moment the keyboard's /dev/input/event6 is deleted
# (every sleep/wake, detach, or our own HID rebind) its "touchevent-dump" thread
# degenerates into a pure-userspace busy-loop and pegs one CPU core forever,
# clinging to the dead fd and never recovering. Confirmed un-fixable short of a
# binary patch; disabling has zero functional impact.
#
# It is an init `oneshot` service, so a single `stop` keeps it dead for the whole
# session (init never respawns a oneshot). We catch it as early as possible after
# init launches it at boot.
LOG=/data/adb/kbd/notec.log
mkdir -p /data/adb/kbd
up() { cut -d' ' -f1 /proc/uptime; }

(
  # Wait (up to ~120s) for init to start it, then stop it once.
  i=0
  while [ $i -lt 600 ]; do
    if [ "$(getprop init.svc.toucheventcheck)" = running ]; then
      stop toucheventcheck
      sleep 0.5
      echo "$(up)  stopped (was running) -> $(getprop init.svc.toucheventcheck)" >> "$LOG"
      break
    fi
    i=$((i + 1)); sleep 0.2
  done
  # Guard a short while in case of a late/again start (oneshot shouldn't respawn).
  j=0
  while [ $j -lt 20 ]; do
    [ "$(getprop init.svc.toucheventcheck)" = running ] && {
      stop toucheventcheck; echo "$(up)  re-stopped" >> "$LOG"; }
    j=$((j + 1)); sleep 1
  done
  echo "$(up)  done; final state=$(getprop init.svc.toucheventcheck)" >> "$LOG"
) &
