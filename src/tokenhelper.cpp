// tokenhelper — tiny bridge between the keyboard handshake (shell) and the
// MiDevAuth TrustZone HAL (midevauthd) on the Xiaomi Pad 7 Pro (muyu).
//
// It performs ONE binder call: IMidevauthService.devauth_token_get(type, uid,
// keyMeta, challenge) and prints the resulting token as hex. The keyboard
// re-auth handshake itself is driven by the shell script that calls this.
//
// Usage:
//   tokenhelper token  <type> <uid_hex> <keyMeta_hex> <challenge_hex>
//   tokenhelper verify <type> <uid_hex> <keyMeta_hex> <challenge_hex> <kbdToken_hex>
//   tokenhelper keyver
//   tokenhelper offlinecheck <keyMeta_hex>
// Prints the result (token as hex, or an int) to stdout; errors to stderr.

#include <aidl/vendor/xiaomi/hardware/aidl/midevauth/IMidevauthService.h>
#include <android/binder_auto_utils.h>
#include <dlfcn.h>
// AServiceManager_* lives in android/binder_manager.h, which is a system/LLNDK
// header absent from the public NDK. Resolve it at runtime from the device's
// libbinder_ndk.so via dlsym so we only link against NDK-public symbols.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

using aidl::vendor::xiaomi::hardware::aidl::midevauth::IMidevauthService;

static int nib(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    c = (char)(c | 0x20);
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

static bool parse_hex(const char* s, std::vector<uint8_t>& out) {
    out.clear();
    for (size_t i = 0; s[i]; ) {
        if (s[i] == ' ' || s[i] == ':') { i++; continue; }      // allow "aa bb" / "aa:bb"
        int hi = nib(s[i]);
        int lo = s[i + 1] ? nib(s[i + 1]) : -1;
        if (hi < 0 || lo < 0) return false;
        out.push_back((uint8_t)((hi << 4) | lo));
        i += 2;
    }
    return true;
}

static void print_hex(const std::vector<uint8_t>& v) {
    for (uint8_t b : v) printf("%02x", b);
    printf("\n");
}

static std::shared_ptr<IMidevauthService> get_service() {
    const char* name = "vendor.xiaomi.hardware.aidl.midevauth.IMidevauthService/default";
    void* h = dlopen("libbinder_ndk.so", RTLD_NOW);
    if (!h) { fprintf(stderr, "tokenhelper: dlopen libbinder_ndk.so: %s\n", dlerror()); return nullptr; }
    using fn_t = AIBinder* (*)(const char*);
    AIBinder* raw = nullptr;
    if (auto w = (fn_t)dlsym(h, "AServiceManager_waitForService")) raw = w(name);
    else if (auto g = (fn_t)dlsym(h, "AServiceManager_getService")) raw = g(name);
    else { fprintf(stderr, "tokenhelper: no AServiceManager_* symbol\n"); return nullptr; }
    if (!raw) { fprintf(stderr, "tokenhelper: service '%s' not found\n", name); return nullptr; }
    ndk::SpAIBinder bin(raw);
    auto svc = IMidevauthService::fromBinder(bin);
    if (!svc) fprintf(stderr, "tokenhelper: fromBinder returned null\n");
    return svc;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: tokenhelper <token|verify|keyver|offlinecheck> ...\n");
        return 2;
    }
    const std::string cmd = argv[1];
    auto svc = get_service();
    if (!svc) return 3;

    if (cmd == "keyver") {
        int32_t v = -1;
        auto st = svc->devauth_key_version(&v);
        if (!st.isOk()) { fprintf(stderr, "key_version: %s\n", st.getDescription().c_str()); return 4; }
        printf("%d\n", v);
        return 0;
    }

    if (cmd == "offlinecheck") {
        if (argc < 3) { fprintf(stderr, "offlinecheck <keyMeta_hex>\n"); return 2; }
        std::vector<uint8_t> km;
        if (!parse_hex(argv[2], km)) { fprintf(stderr, "bad hex\n"); return 2; }
        int32_t r = -1;
        auto st = svc->devauth_OfflineMasterKey_check(km, &r);
        if (!st.isOk()) { fprintf(stderr, "offline_check: %s\n", st.getDescription().c_str()); return 4; }
        printf("%d\n", r);   // 0 == valid (per stock chooseKey)
        return 0;
    }

    if (cmd == "token" || cmd == "verify") {
        int need = (cmd == "token") ? 6 : 7;
        if (argc < need) { fprintf(stderr, "not enough args for %s\n", cmd.c_str()); return 2; }
        int type = atoi(argv[2]);
        std::vector<uint8_t> uid, km, ch;
        if (!parse_hex(argv[3], uid) || !parse_hex(argv[4], km) || !parse_hex(argv[5], ch)) {
            fprintf(stderr, "bad hex in uid/keyMeta/challenge\n"); return 2;
        }
        if (cmd == "token") {
            std::vector<uint8_t> out;
            auto st = svc->devauth_token_get(type, uid, km, ch, &out);
            if (!st.isOk()) { fprintf(stderr, "token_get: %s\n", st.getDescription().c_str()); return 4; }
            if (out.empty()) { fprintf(stderr, "token_get: empty token\n"); return 5; }
            print_hex(out);
            return 0;
        } else {
            std::vector<uint8_t> tok;
            if (!parse_hex(argv[6], tok)) { fprintf(stderr, "bad hex token\n"); return 2; }
            int32_t r = -1;
            auto st = svc->devauth_token_verify(type, uid, km, ch, tok, &r);
            if (!st.isOk()) { fprintf(stderr, "token_verify: %s\n", st.getDescription().c_str()); return 4; }
            printf("%d\n", r);  // 1 online pass, 2 offline pass, else fail
            return 0;
        }
    }

    fprintf(stderr, "unknown command '%s'\n", cmd.c_str());
    return 2;
}
