# Xiaomi Pad 7 Pro keyboard fix (custom ROMs)

Make the **Xiaomi Pad 7 Pro** magnetic keyboard fully work on **crDroid / AOSP
custom ROMs** by completing the keyboard's authentication handshake — using the
tablet's **own TrustZone key**, no Xiaomi cloud, no secret extraction.

> Device codename **`muyu`** (Xiaomi Pad 7 Pro, `24091RPADG`). Rooted with
> Magisk. Tested on crDroid 12.7 (Android 16).

> ### ⚠️ New approach (this replaces the old one)
>
> The previous fix in this repo — a Magisk module that rebound the keyboard's
> HID device — did **not** reliably solve the problem. It's preserved on the
> [`legacy-hid-rebind`](../../tree/legacy-hid-rebind) branch.
>
> This version fixes the real cause: it **completes the keyboard's
> authentication** using the tablet's own TrustZone key. See below.


## The problem

The Xiaomi keyboard periodically asks the tablet to authenticate (Xiaomi's
"MiAuth"). Stock HyperOS answers with `MiDevAuthService` + the `midevauthd` HAL,
which talk to a signed **TrustZone trustlet** holding a per-device key. Custom
ROMs ship neither, so the handshake never completes — which can leave the
keyboard misbehaving.

You **cannot** fake the answer: the keyboard's challenge carries a random nonce
and the response is a keyed MAC, so replaying a captured token doesn't work. The
real key is required.

## The insight

On this device the **entire TrustZone path is still present under crDroid**:

* `/dev/smcinvoke` + the `smcinvoke`/`qseecom_proxy` kernel modules,
* the TEE client libs in `/vendor/lib64` (`libQSEEComAPI.so`, ...),
* and the trustlet itself: `/vendor/firmware_mnt/image/devauth.*`.

The only missing piece is Xiaomi's thin HAL daemon `midevauthd`. Copy that over,
and it loads the trustlet and computes real tokens — **offline**, under
**Enforcing SELinux**.

## How it works

```
[keyboard] -- /dev/nanodev0 -- kbd_auth.sh -- tokenhelper --(vndbinder)--
                                           midevauthd --(smcinvoke)-- devauth trustlet (key)
```

* **`midevauthd`** - Xiaomi's HAL daemon (proprietary; copied from the stock ROM,
  not distributed here). Loads the trustlet, serves `IMidevauthService`.
* **`tokenhelper`** - a tiny binder client (this repo; prebuilt in Releases) that
  calls `IMidevauthService.devauth_token_get(type, uid, keyMeta, challenge)` and
  prints the 16-byte token. A shell script can't do a binder call with byte-array
  arguments, so this is the one native piece.
* **`kbd_auth.sh`** - drives the keyboard handshake on `/dev/nanodev0`
  (`AUTH_START -> STEP3 -> STEP5`) and asks `tokenhelper` for the STEP5 token.

Two things that trip people up (both already handled by the scripts):

1. `midevauthd` registers with the **vendor** servicemanager, so the client must
   use the **vendor** `libbinder` - run `tokenhelper` with
   `LD_LIBRARY_PATH=/vendor/lib64:/system/lib64` (binds `/dev/vndbinder`).
2. Nothing proactively starts auth on a custom ROM, so `kbd_auth.sh` sends one
   `AUTH_START` at launch and then answers every re-auth request.

## Requirements

* Xiaomi Pad 7 Pro (`muyu`) on a custom ROM that uses the **HyperOS vendor
  blobs** (so the trustlet + TEE libs are present). Check:
  `ls /vendor/firmware_mnt/image/devauth.*` and `ls /dev/smcinvoke`.
* Root (Magisk).
* `adb`.
* Three proprietary files from a **stock HyperOS ROM for `muyu`** (see below).

## Install

### 1. Get `tokenhelper`

Download `tokenhelper` from the [latest Release](../../releases/latest), or build
it yourself (see *Building*). It's a static-libc++ arm64 binary; no extra runtime
deps.

### 2. Get the three Xiaomi HAL files

These are Xiaomi proprietary and are **not** included here. Extract them from a
stock HyperOS fastboot ROM for `muyu` (unpack `odm.img`, which is EROFS):

| From the stock ROM (`odm` partition) |
| --- |
| `/odm/bin/midevauthd` |
| `/odm/lib64/libmidevauth.so` |
| `/odm/lib64/vendor.xiaomi.hardware.aidl.midevauth-V1-ndk_platform.so` |

(Tools: `payload-dumper` for `payload.bin`, then `extract.erofs` / `fsck.erofs -x`
on `odm.img`.)

### 3. Push everything and enable at boot

```sh
su -c 'mkdir -p /data/adb/kbdauth'
adb push midevauthd libmidevauth.so \
         vendor.xiaomi.hardware.aidl.midevauth-V1-ndk_platform.so \
         tokenhelper device/kbd_auth.sh /data/adb/kbdauth/
adb push device/service.d-kbdauth.sh /data/adb/service.d/kbdauth.sh
su -c 'chmod 755 /data/adb/kbdauth/midevauthd /data/adb/kbdauth/tokenhelper \
               /data/adb/kbdauth/kbd_auth.sh /data/adb/service.d/kbdauth.sh'
```

Reboot. On boot the launcher waits for the system + `/dev/nanodev0`, starts
`midevauthd`, waits for it to register, then starts `kbd_auth.sh`.

### 4. Verify

```sh
su -c 'cat /data/adb/kbd/svc.log'     # daemon started, vnd=1
su -c 'cat /data/adb/kbd/auth.log'    # "-> STEP5 sent (real token)"
# quick HAL check (daemon must be running):
su -c 'cd /data/adb/kbdauth; LD_LIBRARY_PATH=/vendor/lib64:/system/lib64 ./tokenhelper keyver'   # prints 2
```

## Building `tokenhelper`

The [GitHub Actions workflow](.github/workflows/build.yml) cross-compiles it for
`arm64-v8a` with the Android NDK - no local toolchain needed. Pushing a tag `v*`
also publishes a Release with the binary attached.

Locally (Linux, Android SDK + NDK r26):

```sh
AIDL=$ANDROID_HOME/build-tools/34.0.0/aidl
NDK=$ANDROID_HOME/ndk/26.3.11579264
CXX=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android31-clang++
$AIDL --lang=ndk --structured --stability=vintf -I aidl -o gen -h gen \
  aidl/vendor/xiaomi/hardware/aidl/midevauth/IMidevauthService.aidl
$CXX -std=c++17 -O2 -fPIE -pie -static-libstdc++ -I gen \
  src/tokenhelper.cpp $(find gen -name '*.cpp') -lbinder_ndk -llog -ldl -o tokenhelper
```

> NDK **r26** is used on purpose: r30 dropped the AIDL-NDK C++ wrapper headers.
> `AServiceManager_*` isn't in the public NDK, so `tokenhelper` resolves it at
> runtime via `dlsym` from `libbinder_ndk.so`.

## Uninstall

```sh
su -c 'rm /data/adb/service.d/kbdauth.sh; pkill -f midevauthd; pkill -f kbd_auth.sh'
# optional: rm -rf /data/adb/kbdauth
```

## Troubleshooting

* `tokenhelper` hangs -> you didn't use the vendor `libbinder`
  (`LD_LIBRARY_PATH=/vendor/lib64:/system/lib64`), so it can't see the vendor
  service. Confirm the daemon is registered:
  `su -c 'vndservice list | grep midevauth'`.
* `svc.log` shows `vnd=0` -> `midevauthd` didn't register. Check `d.log`; confirm
  the trustlet exists (`ls /vendor/firmware_mnt/image/devauth.*`) and
  `/dev/smcinvoke` is present.
* `token_get FAILED` in `auth.log` -> the daemon isn't up, or the libs path is
  wrong.

## Repository layout

```
aidl/.../IMidevauthService.aidl   reconstructed HAL interface (interface only;
                                  order puts devauth_token_get at code 17)
src/tokenhelper.cpp               the binder client
device/kbd_auth.sh                the keyboard handshake driver
device/service.d-kbdauth.sh       Magisk boot launcher
device/start.sh                   manual (non-boot) launcher
.github/workflows/build.yml       CI build + tagged Release
```

## Credits & license

Reverse-engineered by inspecting the device's own stock components for
interoperability/repair. No Xiaomi proprietary binaries or keys are included in
this repository. Our code is released under the MIT License (see `LICENSE`).
