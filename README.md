# Xiaomi Pad 7 Pro keyboard fix (custom ROMs) - v3

Make the **Xiaomi Pad 7 / 7 Pro** magnetic keyboard fully work on **crDroid /
AOSP custom ROMs**: no dropouts, it actually types at boot, correct arrow-key
orientation, working **Caps Lock LED**, and a **keyboard-backlight** shortcut.

> Codename `muyu` (Pad 7 Pro) / `uke` (Pad 7). **Root required** (Magisk or
> KernelSU) - but **no Magisk module**: it's all `/data/adb` boot scripts that
> the root manager runs at startup. v2 (auth only) is on the `v2-backup` branch.

## What it fixes

| Problem on a custom ROM | Fix |
| --- | --- |
| Keyboard "connected" but **types nothing** at boot | `xiaomi_kbd_service.sh` - rebinds the HID so Android enables the input |
| Keyboard **stops after a while** (drops keys) | `kbd_auth.sh` + `midevauthd` - completes Xiaomi MiAuth with the device's own TrustZone key |
| **Arrow keys rotated** 90 degrees | IDC `device.internal = 0` (via `post-fs-data`) |
| **Caps Lock LED** dead | `kbd_leds.sh` - driven from the Caps key |
| **Keyboard backlight** dead | `kbd_leds.sh` - **Ctrl+Alt+4 brighter / Ctrl+Alt+3 dimmer** (0 = off) |
| **One CPU core stuck at 100%** / tablet runs warm | `kbd_no_toucheventcheck.sh` - disables Xiaomi's `toucheventcheck` telemetry daemon, which busy-loops when the keyboard's input node is removed |

Nothing contacts Xiaomi servers and no keys are extracted: the token is computed
on-device by the signed `devauth` TrustZone trustlet already in your firmware.

## Components (all run as root via Magisk's boot scripts)

```
/data/adb/post-fs-data.d/kbd_idc.sh   -> writes the keyboard IDC early (arrow-key + external-device flags)
/data/adb/post-fs-data.d/kbd_no_toucheventcheck.sh -> disables the toucheventcheck telemetry daemon (100% CPU fix)
/data/adb/service.d/kbdauth.sh        -> starts midevauthd + kbd_auth.sh + kbd_leds.sh
/data/adb/service.d/xiaomi_kbd_service.sh -> rebinds the HID while connected (enables typing)
/data/adb/kbdauth/                    -> midevauthd + libs (you supply) + tokenhelper + kbd_auth.sh + kbd_leds.sh
```

* **`midevauthd`** - Xiaomi's HAL daemon (proprietary; copied from the stock ROM, not distributed here).
* **`tokenhelper`** - tiny binder client (this repo; prebuilt in Releases) that calls `IMidevauthService.devauth_token_get`.
* **`kbd_auth.sh`** - drives the keyboard MiAuth handshake and sends the token.
* **`kbd_leds.sh`** - Caps Lock LED (acts on the Caps key) + backlight (Ctrl+Alt+3/4, level 0-100 via cmd `0x23`).
* **`xiaomi_kbd_service.sh`** - **required**; without it Android leaves the HID disabled and the keyboard types nothing.
* **`kbd_no_toucheventcheck.sh`** - stops Xiaomi's `toucheventcheck` (a MiSight *telemetry* daemon, not a driver) at boot. On a custom ROM it busy-loops a CPU core forever once the keyboard's input node is deleted; disabling it has no functional impact. See *Notes*.

## Requirements

* Pad 7 / 7 Pro on a custom ROM using the HyperOS vendor blobs. Check:
  `ls /vendor/firmware_mnt/image/devauth.*` and `ls /dev/smcinvoke`.
* Root (Magisk or KernelSU), `adb`.
* Three proprietary files from a stock HyperOS ROM for your codename (below).

## Install

### 1. Get `tokenhelper`
From the [latest Release](../../releases/latest) (static arm64, no runtime deps), or build it (see *Building*).

### 2. Get the three Xiaomi HAL files
Not included here. Extract from a stock HyperOS fastboot ROM (`odm.img` is EROFS):

| From the stock ROM `odm` partition |
| --- |
| `/odm/bin/midevauthd` |
| `/odm/lib64/libmidevauth.so` |
| `/odm/lib64/vendor.xiaomi.hardware.aidl.midevauth-V1-ndk_platform.so` |

### 3. Push everything and enable at boot
`/data/adb` is root-only, so stage in `/data/local/tmp` and copy as root:

```sh
adb push midevauthd libmidevauth.so \
         vendor.xiaomi.hardware.aidl.midevauth-V1-ndk_platform.so \
         tokenhelper device/kbd_auth.sh device/kbd_leds.sh \
         device/service.d-kbdauth.sh device/xiaomi_kbd_service.sh \
         device/post-fs-data-kbd-idc.sh device/kbd_no_toucheventcheck.sh /data/local/tmp/
adb shell su -c '
  mkdir -p /data/adb/kbdauth /data/adb/service.d /data/adb/post-fs-data.d
  cp /data/local/tmp/{midevauthd,libmidevauth.so,vendor.xiaomi.hardware.aidl.midevauth-V1-ndk_platform.so,tokenhelper,kbd_auth.sh,kbd_leds.sh} /data/adb/kbdauth/
  cp /data/local/tmp/service.d-kbdauth.sh    /data/adb/service.d/kbdauth.sh
  cp /data/local/tmp/xiaomi_kbd_service.sh   /data/adb/service.d/xiaomi_kbd_service.sh
  cp /data/local/tmp/post-fs-data-kbd-idc.sh /data/adb/post-fs-data.d/kbd_idc.sh
  cp /data/local/tmp/kbd_no_toucheventcheck.sh /data/adb/post-fs-data.d/kbd_no_toucheventcheck.sh
  chmod 755 /data/adb/kbdauth/midevauthd /data/adb/kbdauth/tokenhelper \
            /data/adb/kbdauth/kbd_auth.sh /data/adb/kbdauth/kbd_leds.sh \
            /data/adb/service.d/kbdauth.sh /data/adb/service.d/xiaomi_kbd_service.sh \
            /data/adb/post-fs-data.d/kbd_idc.sh /data/adb/post-fs-data.d/kbd_no_toucheventcheck.sh
'
```

Reboot.

### 4. Verify
```sh
su -c 'cat /data/adb/kbd/svc.log'     # daemon started, vnd=1
su -c 'cat /data/adb/kbd/auth.log'    # "-> STEP5 sent (real token)"
su -c 'cat /data/adb/kbd/leds.log'    # caps/keys EVDEV discovered
```
Then use the keyboard: type, toggle Caps Lock, and press **Ctrl+Alt+4 / Ctrl+Alt+3** for backlight.

## Backlight combo

The keyboard has no dedicated backlight key, so backlight is bound to a safe,
rarely-used combo: **Ctrl+Alt+4 = brighter, Ctrl+Alt+3 = dimmer** (down to 0 =
off, up from 0 = on). Tunables at the top of `kbd_leds.sh`: `BL_STEP`,
`BL_DEFAULT`, `BL_MAX`, and `BL_NEED_CTRL` / `BL_NEED_ALT` / `BL_KEY_UP` /
`BL_KEY_DOWN` (e.g. set `BL_NEED_ALT=0` for plain `Ctrl+3/4`). Note: the combo is
observed, not consumed, so pick one your apps don't use.

## Building `tokenhelper`
[GitHub Actions](.github/workflows/build.yml) cross-compiles it for `arm64-v8a`
(NDK r26); pushing a `v*` tag also publishes a Release. The binary is unchanged
since v2 (same source).

## Uninstall
```sh
su -c 'rm /data/adb/service.d/kbdauth.sh /data/adb/service.d/xiaomi_kbd_service.sh \
          /data/adb/post-fs-data.d/kbd_idc.sh /data/adb/post-fs-data.d/kbd_no_toucheventcheck.sh
       rm -f /data/system/devices/idc/Vendor_15d9_Product_00a3.idc
       pkill -f midevauthd; pkill -f kbd_auth.sh; pkill -f kbd_leds.sh
       start toucheventcheck'   # re-enable the telemetry daemon (or just reboot)
# optional: rm -rf /data/adb/kbdauth
```

## Notes
* `midevauthd` registers with the **vendor** servicemanager, so `tokenhelper` runs with `LD_LIBRARY_PATH=/vendor/lib64:/system/lib64` (vndbinder).
* Caps Lock: Android emits `LED_CAPSL` only on the *next* key, and the keyboard applies an LED change only on activity - so we act on the `KEY_CAPSLOCK` press and use `LED_CAPSL` only to correct drift.
* Arrow keys: fixed via `device.internal = 0` in the IDC; harmless where arrows were already correct.
* IDC precedence: `/system/usr/idc` beats `/data/system/devices/idc`, so this ships the IDC only in `/data` and uses **no** Magisk module (which would otherwise mount a competing `/system` copy).
* `toucheventcheck`: Xiaomi's `/odm/bin/toucheventcheck` is a MiSight *touch-telemetry* daemon (not the touch driver - that's the separate `touchfeature-service`). It opens every input node, and when the keyboard's node is deleted (sleep/wake, detach, or our own HID rebind) its dump thread degenerates into a pure-userspace busy-loop that pegs one core forever and never recovers. Since it's a `oneshot` init service, `kbd_no_toucheventcheck.sh` just `stop`s it at boot and init never respawns it. Alternative considered and rejected: restart it on every rebind - that keeps it alive (and it only re-spins on the next sleep/wake), and it's merely telemetry, so disabling outright is cleaner. Logs to `/data/adb/kbd/notec.log`.

## License
MIT (see `LICENSE`). Reverse-engineered from the device's own components for interoperability/repair; no Xiaomi binaries or keys included.
