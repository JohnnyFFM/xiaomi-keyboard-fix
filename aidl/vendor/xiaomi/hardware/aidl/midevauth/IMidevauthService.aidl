// Reconstructed from the on-device HAL (decompiled MiDevAuthService.apk).
// Method ORDER here must match the original AIDL so transaction codes line up:
//   token_verify -> 16, token_get -> 17.  (jadx lists methods alphabetically; the
//   TRANSACTION_* constants reveal the true order, reproduced below.)
// No Xiaomi proprietary code is included — this is an interface description only,
// written for interoperability with the device's own signed trustlet.
package vendor.xiaomi.hardware.aidl.midevauth;

@VintfStability
interface IMidevauthService {
    int    devauth_AllPersistData_clean();                                           // 1
    int    devauth_BlackUidList_load(String s);                                      // 2
    int    devauth_BlackUid_check(in byte[] b);                                      // 3
    String devauth_CAVersion_get();                                                  // 4
    int    devauth_OfflineMasterKey_check(in byte[] b);                              // 5
    int    devauth_OnlineDerivedKey_check(in byte[] a, in byte[] b);                 // 6
    int    devauth_OnlineDerivedkey_load(String s);                                  // 7
    String devauth_OnlineKey_WithUid_prepare(String s);                              // 8
    String devauth_UidList_get();                                                    // 9
    String devauth_UidList_prepare(String s);                                        // 10
    byte[] devauth_challenge_get(int i);                                             // 11
    String devauth_key_dump();                                                       // 12
    int    devauth_key_load(String a, String b);                                     // 13
    String devauth_key_prepare();                                                    // 14
    int    devauth_key_version();                                                    // 15
    int    devauth_token_verify(int i, in byte[] a, in byte[] b, in byte[] c, in byte[] d); // 16
    byte[] devauth_token_get(int i, in byte[] uid, in byte[] keyMeta, in byte[] challenge); // 17
}
