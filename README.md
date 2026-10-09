# Xiaomi Pad 7 Pro keyboard fix (custom ROMs) - v3

Make the **Xiaomi Pad 7 / 7 Pro** magnetic keyboard fully work on **crDroid /
AOSP custom ROMs**: no dropouts, the keyboard actually types at boot, and the
**Caps Lock LED** and **backlight** work too.

> Codename `muyu` (Pad 7 Pro) / `uke` (Pad 7). Rooted with Magisk. Tested on
> crDroid (Android 16). v2 (auth only) is preserved on the `v2-backup` branch.

## What it fixes

| Problem on custom ROMs | Fix |
| --- | --- |
| Keyboard "connected" but **types nothing** at boot | `xiaomi_kbd_service.sh` - rebinds the HID so Android enables the input |
| Keyboard **stops after a while** (drops key reports) | `kbd_auth.sh` + `midevauthd` - completes Xiaomi's MiAuth using the device's own TrustZone key |
| **Caps Lock LED** dead | `kbd_leds.sh` - drives the LED from the Caps key |
| **Keyboard backlight** dead | `kbd_leds.sh` - the backlight keys (Fn) adjust it |

Nothing here contacts Xiaomi servers and no keys are extracted: the token is
computed on-device by the signed `devauth` TrustZone trustlet that's already in
your firmware.

## Components

```
[keyboard] -- /dev/nanodev0 -- kbd_auth.sh ---- tokenhelper --(vndbinder)-- midevauthd --(smcinvoke)-- devauth trustlet
           \- /dev/input/ev* - kbd_leds.sh (Caps LED + backlight keys)
           \- HID bind ------- xiaomi_kbd_service.sh (enables the input at boot)
```

* **`midevauthd`** - Xiaomi's HAL daemon (proprietary; copied from the stock ROM,
  not distributed here).
* **`tokenhelper`** - tiny binder client (this repo; prebuilt in Releases) that
  calls `IMidevauthService.devauth_token_get`.
* **`kbd_auth.sh`** - drives the keyboard MiAuth handshake and sends the token.
* **`kbd_leds.sh`** - Caps Lock LED (acts on the Caps key; the LED change is
  applied on the key activity) and backlight (the keyboard's own
  `KBDILLUM` Up/Down/Toggle keys, 0-100, cmd `0x23`).
* **`xiaomi_kbd_service.sh`** - rebinds the HID while connected so Android keeps
  the input enabled. **Required** - without it the keyboard types nothing.

## Requirements

* Pad 7 / 7 Pro on a custom ROM using the HyperOS vendor blobs (so the trustlet +
  TEE libs are present). Check: `ls /vendor/firmware_mnt/image/devauth.*` and
  `ls /dev/smcinvoke`.
* Root (Magisk), `adb`.
* Three proprietary files from a stock HyperOS ROM for your codename (below).

## Install

### 1. Get `tokenhelper`

Download it from the [latest Release](../../releases/latest), or build it (see
*Building*). Static arm64 binary, no runtime deps.

### 2. Get the three Xiaomi HAL files

Not included here (Xiaomi proprietary). Extract from a stock HyperOS fastboot ROM
(unpack `odm.img`, which is EROFS):

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
         device/service.d-kbdauth.sh device/xiaomi_kbd_service.sh /data/local/tmp/
adb shell su -c '
  mkdir -p /data/adb/kbdauth
  cp /data/local/tmp/{midevauthd,libmidevauth.so,vendor.xiaomi.hardware.aidl.midevauth-V1-ndk_platform.so,tokenhelper,kbd_auth.sh,kbd_leds.sh} /data/adb/kbdauth/
  cp /data/local/tmp/service.d-kbdauth.sh   /data/adb/service.d/kbdauth.sh
  cp /data/local/tmp/xiaomi_kbd_service.sh  /data/adb/service.d/xiaomi_kbd_service.sh
  chmod 755 /data/adb/kbdauth/midevauthd /data/adb/kbdauth/tokenhelper \
            /data/adb/kbdauth/kbd_auth.sh /data/adb/kbdauth/kbd_leds.sh \
            /data/adb/service.d/kbdauth.sh /data/adb/service.d/xiaomi_kbd_service.sh
'
```

Reboot. Two boot services come up: `kbdauth.sh` (HAL + auth bridge + LEDs) and
`xiaomi_kbd_service.sh` (HID enable).

### 4. Verify

```sh
su -c 'cat /data/adb/kbd/svc.log'     # daemon started, vnd=1
su -c 'cat /data/adb/kbd/auth.log'    # "-> STEP5 sent (real token)"
su -c 'cat /data/adb/kbd/leds.log'    # caps/illum EVDEV discovered
su -c 'cd /data/adb/kbdauth; LD_LIBRARY_PATH=/vendor/lib64:/system/lib64 ./tokenhelper keyver'   # prints 2
```

Then just use the keyboard: type, toggle Caps Lock, press the backlight keys.

## Building `tokenhelper`

[GitHub Actions](.github/workflows/build.yml) cross-compiles it for `arm64-v8a`
with the Android NDK; pushing a `v*` tag also publishes a Release with the
binary. Locally (Linux, SDK + NDK r26):

```sh
AIDL=$ANDROID_HOME/build-tools/34.0.0/aidl
NDK=$ANDROID_HOME/ndk/26.3.11579264
CXX=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android31-clang++
$AIDL --lang=ndk --structured --stability=vintf -I aidl -o gen -h gen \
  aidl/vendor/xiaomi/hardware/aidl/midevauth/IMidevauthService.aidl
$CXX -std=c++17 -O2 -fPIE -pie -static-libstdc++ -I gen \
  src/tokenhelper.cpp $(find gen -name '*.cpp') -lbinder_ndk -llog -ldl -o tokenhelper
```

## Uninstall

```sh
su -c 'rm /data/adb/service.d/kbdauth.sh /data/adb/service.d/xiaomi_kbd_service.sh
       pkill -f midevauthd; pkill -f kbd_auth.sh; pkill -f kbd_leds.sh'
# optional: rm -rf /data/adb/kbdauth
```

## Notes & quirks (for the curious)

* `midevauthd` registers with the **vendor** servicemanager, so the client must
  use the vendor `libbinder`; `kbd_auth.sh` runs `tokenhelper` with
  `LD_LIBRARY_PATH=/vendor/lib64:/system/lib64` (binds `/dev/vndbinder`).
* The keyboard's challenge nonce is random, so you can't replay a captured token
  - the real key (trustlet) is required. That's why `midevauthd` is needed.
* Caps Lock: Android emits `LED_CAPSL` only on the *next* key after the Caps
  press, and the keyboard applies an LED change only on activity - so we act on
  the `KEY_CAPSLOCK` press itself and use `LED_CAPSL` only to correct drift.
* Backlight is a 0-100 level (cmd `0x23`); stock also auto-dims it via the light
  sensor - not replicated here (the Fn backlight keys are).

## License

MIT (see `LICENSE`). Reverse-engineered from the device's own components for
interoperability/repair; no Xiaomi binaries or keys are included.
