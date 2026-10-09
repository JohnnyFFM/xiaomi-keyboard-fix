#!/system/bin/sh
# kbd_auth.sh - complete the Xiaomi keyboard MiAuth handshake on crDroid using the
# device's own MiDevAuth TrustZone HAL (midevauthd) via the tokenhelper binder client.
DEV=/dev/nanodev0
DIR=/data/adb/kbd
LOG=$DIR/auth.log
TAG=xiaomi_kbd_auth
HELPER=${HELPER:-/data/local/tmp/mda/tokenhelper}
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
sum_hex() { s=0; for h in "$@"; do s=$((s + 0x$h)); done; printf '%02x' $((s & 255)); }

send_auth_start() {
    body="4f 31 80 38 31 06 4d 49 41 55 54 48"
    send_frame 32 00 $body $(sum_hex $body)
}
send_step3_chal() {   # $1..$4 keyMeta, $5..$20 challenge (16 bytes)
    km="$1 $2 $3 $4"; shift 4
    body="4f 31 80 38 32 14 $km $*"
    send_frame 32 00 $body $(sum_hex $body)
}

send_step3() {
    chal=$(od -An -N16 -tx1 /dev/urandom | tr -s ' \n' ' ' | sed 's/^ //;s/ $//')
    send_step3_chal $1 $2 $3 $4 $chal
}
send_step5() {
    body="4f 31 80 38 33 10 $*"
    send_frame 32 00 $body $(sum_hex $body)
}
choose_keymeta() {
    if [ $(( 0x$1 & 0x40 )) -ne 64 ]; then echo "$1 $2 $3 $4"; else echo "$5 $6 $7 $8"; fi
}


logline "## kbd_auth start (helper=$HELPER)"
log -t "$TAG" "kbd_auth start"
[ -x "$HELPER" ] || logline "WARN: $HELPER not executable yet"
exec 3< "$DEV" || { logline "## open failed"; exit 1; }
UID_HEX=""; KM=""
send_auth_start; logline "cold AUTH_START kick"
carry=""
while true; do
    chunk=$(dd bs=128 count=1 2>/dev/null <&3 | od -An -v -tx1 | tr -d '\n' | tr -s ' ')
    [ -z "$chunk" ] && { sleep 1; continue; }
    set -- $carry $chunk
    carry=""
    while [ $# -ge 1 ]; do
        case "$1" in 22) n=16;; 23) n=32;; 24|26) n=0;; *) shift; continue;; esac
        if [ "$2 $3 $4" != "31 38 80" ]; then shift; continue; fi
        if [ "$6 $7 $8" = "31 38 80" ]; then shift; shift; shift; shift; continue; fi
        if [ $n -eq 0 ]; then
            if [ $# -lt 7 ]; then carry="$*"; break; fi
            n=$((7 + 0x$6))
        fi
        if [ $# -lt $n ]; then case "$1" in 24|26) carry="$*";; esac; break; fi
        cmd=$5; len=$6; val=$7
        case "$cmd" in
            24)
                [ "$val" = "64" ] && { logline "REAUTH -> AUTH_START"; send_auth_start; }
                [ "$val" = "01" ] && { logline "INIT -> AUTH_START"; send_auth_start; }
                ;;
            31)
                uid=$(echo $* | cut -d' ' -f9-24)
                k1=$(echo $* | cut -d' ' -f25-28)
                k2=$(echo $* | cut -d' ' -f29-32)
                KM=$(choose_keymeta $k1 $k2)
                UID_HEX="$uid"
                logline "0x31 uid=$uid km1=$k1 km2=$k2 chosen=$KM"
                send_step3 $KM
                logline "-> STEP3 (random challenge)"
                ;;
            32)
                if [ "$len" != "20" ]; then logline "0x32 len=0x$len not 32B, skip"; else
                    ktok=$(echo $* | cut -d' ' -f7-22)
                    kchal=$(echo $* | cut -d' ' -f23-38)
                    logline "0x32 kbdToken=$ktok kbdChallenge=$kchal"
                    tok=$(LD_LIBRARY_PATH=/vendor/lib64:/system/lib64 "$HELPER" token 1 "$UID_HEX" "$KM" "$kchal" 2>>"$LOG")
                    if [ -n "$tok" ]; then
                        logline "token_get -> $tok ; sending STEP5"
                        send_step5 $(echo $tok | sed 's/../& /g')
                        logline "-> STEP5 sent (real token)"
                    else
                        logline "token_get FAILED; STEP5 not sent"
                    fi
                fi
                ;;
            22) logline "KB_STATUS val=$val";;
        esac
        i=0; while [ $i -lt $n ] && [ $# -gt 0 ]; do shift; i=$((i+1)); done
    done
done
