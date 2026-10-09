#!/system/bin/sh
timeout 14 getevent -l /dev/input/event6 > /data/local/tmp/ge.txt 2>&1
