#!/usr/bin/env python3
"""
Patch script untuk AzaharTrigger-test - Pretendo/Nimbus fixes
Versi 3 - APInfo sebagai raw array 0x34 bytes (aman dari size mismatch)

Perubahan:
  [ac.h]       - APInfo raw array + deklarasi GetCurrentAPInfo
  [ac.cpp]     - Implementasi GetCurrentAPInfo (tulis offset langsung)
  [ac_u.cpp]   - 0x000E nullptr -> &AC_U::GetCurrentAPInfo
  [ac_i.cpp]   - 0x000E nullptr -> &AC_I::GetCurrentAPInfo
  [plgldr.cpp] - Fix commit 6d72a6f + GetVersion 0x000E
  [plgldr.h]   - Deklarasi GetVersion

Usage:
  python3 patch_pretendo_fixes.py <repo_root>
"""

import sys, os

def patch(path, old, new, label):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    if new in content:
        print(f"  [SKIP] '{label}' - sudah ada di {os.path.basename(path)}")
        return False
    if old not in content:
        print(f"  [MISS] '{label}' - pattern tidak ditemukan di {os.path.basename(path)}")
        return False
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content.replace(old, new, 1))
    print(f"  [OK]   '{label}' -> {os.path.basename(path)}")
    return True

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 patch_pretendo_fixes.py <repo_root>")
        sys.exit(1)

    root = sys.argv[1]
    ac_cpp  = os.path.join(root, "src/core/hle/service/ac/ac.cpp")
    ac_h    = os.path.join(root, "src/core/hle/service/ac/ac.h")
    ac_u    = os.path.join(root, "src/core/hle/service/ac/ac_u.cpp")
    ac_i    = os.path.join(root, "src/core/hle/service/ac/ac_i.cpp")
    plg_cpp = os.path.join(root, "src/core/hle/service/plgldr/plgldr.cpp")
    plg_h   = os.path.join(root, "src/core/hle/service/plgldr/plgldr.h")

    for p in [ac_cpp, ac_h, ac_u, ac_i, plg_cpp, plg_h]:
        if not os.path.exists(p):
            print(f"[ERROR] File tidak ditemukan: {p}")
            sys.exit(1)
    print("[OK] Semua file ditemukan\n")

    # =========================================================
    # PATCH 1: ac.h - APInfo sebagai raw array 0x34 bytes
    # Menghindari static_assert size mismatch sepenuhnya
    # Layout berdasarkan dokumentasi AC service 3DS:
    #   0x00: bssid[6]
    #   0x06: padding[2]
    #   0x08: ssid[32]
    #   0x28: ssid_len (u8)
    #   0x29: channel (u8)
    #   0x2A: signal_strength (u8)
    #   0x2B: link_level (u8)
    #   0x2C: padding[4]
    #   0x30: network_id (u32)
    #   Total: 0x34 = 52 bytes
    # =========================================================
    print("=== [1/7] ac.h - Tambah APInfo (raw array) ===")
    patch(ac_h,
        old='''    struct ACConfig {
        std::array<u8, 0x200> data;
    };''',
        new='''    struct ACConfig {
        std::array<u8, 0x200> data;
    };

    // APInfo: 0x34 bytes sesuai protokol AC service 3DS
    // Dikembalikan oleh GetCurrentAPInfo (command 0x000E)
    // Disimpan sebagai raw array untuk menghindari masalah padding/alignment
    struct APInfo {
        std::array<u8, 0x34> data{};
    };''',
        label="struct APInfo (raw array)"
    )

    # =========================================================
    # PATCH 2: ac.h - Deklarasi GetCurrentAPInfo
    # =========================================================
    print("=== [2/7] ac.h - Deklarasi GetCurrentAPInfo ===")
    patch(ac_h,
        old='''        void SetClientVersion(Kernel::HLERequestContext& ctx);

    protected:''',
        new='''        void SetClientVersion(Kernel::HLERequestContext& ctx);

        /**
         * AC::GetCurrentAPInfo service function (0x000E)
         * Mengembalikan info AP yang sedang terhubung.
         * Di emulator dikembalikan data dummy agar Nimbus/PIA tidak gagal.
         *  Inputs:
         *      1 : ukuran output buffer
         *      2 : mapped write buffer descriptor
         *      3 : pointer ke buffer output APInfo (0x34 bytes)
         *  Outputs:
         *      1 : Result, 0 = sukses
         *      2 : mapped buffer descriptor
         *      3 : pointer ke buffer output
         */
        void GetCurrentAPInfo(Kernel::HLERequestContext& ctx);

    protected:''',
        label="deklarasi GetCurrentAPInfo"
    )

    # =========================================================
    # PATCH 3: ac.cpp - Implementasi GetCurrentAPInfo
    # Tulis data dummy ke APInfo raw array via offset
    # Offset layout:
    #   [0x00] bssid[6]        = 02:00:00:00:00:01
    #   [0x08] ssid[32]        = "EmulatorAP"
    #   [0x28] ssid_len (u8)   = 10
    #   [0x29] channel (u8)    = 6
    #   [0x2A] signal (u8)     = 100
    #   [0x2B] link_level (u8) = 3
    #   [0x30] network_id (u32)= 1
    # =========================================================
    print("=== [3/7] ac.cpp - Implementasi GetCurrentAPInfo ===")
    patch(ac_cpp,
        old='''Module::Interface::Interface(std::shared_ptr<Module> ac, const char* name, u32 max_session)
    : ServiceFramework(name, max_session), ac(std::move(ac)) {}''',
        new='''void Module::Interface::GetCurrentAPInfo(Kernel::HLERequestContext& ctx) {
    IPC::RequestParser rp(ctx);
    [[maybe_unused]] u32 size = rp.Pop<u32>();
    auto output_buffer = rp.PopMappedBuffer();

    // Isi APInfo dummy (0x34 bytes) agar Nimbus/PIA dapat melanjutkan autentikasi
    // Offset sesuai layout protokol AC service 3DS
    Module::APInfo ap_info{};
    // BSSID: 02:00:00:00:00:01 (locally administered, emulator dummy)
    ap_info.data[0x00] = 0x02;
    ap_info.data[0x01] = 0x00;
    ap_info.data[0x02] = 0x00;
    ap_info.data[0x03] = 0x00;
    ap_info.data[0x04] = 0x00;
    ap_info.data[0x05] = 0x01;
    // SSID: "EmulatorAP" mulai offset 0x08
    const char* dummy_ssid = "EmulatorAP";
    const u8 ssid_len = static_cast<u8>(std::strlen(dummy_ssid));
    std::memcpy(&ap_info.data[0x08], dummy_ssid, ssid_len);
    // ssid_len di offset 0x28
    ap_info.data[0x28] = ssid_len;
    // channel = 6 di offset 0x29
    ap_info.data[0x29] = 6;
    // signal_strength = 100 di offset 0x2A
    ap_info.data[0x2A] = 100;
    // link_level = 3 di offset 0x2B
    ap_info.data[0x2B] = 3;
    // network_id = 1 di offset 0x30 (little-endian u32)
    ap_info.data[0x30] = 1;
    ap_info.data[0x31] = 0;
    ap_info.data[0x32] = 0;
    ap_info.data[0x33] = 0;

    output_buffer.Write(&ap_info, 0, std::min(output_buffer.GetSize(), sizeof(ap_info)));

    IPC::RequestBuilder rb = rp.MakeBuilder(1, 2);
    rb.Push(ResultSuccess);
    rb.PushMappedBuffer(output_buffer);

    LOG_WARNING(Service_AC, "(STUBBED) called, returning dummy AP info");
}

Module::Interface::Interface(std::shared_ptr<Module> ac, const char* name, u32 max_session)
    : ServiceFramework(name, max_session), ac(std::move(ac)) {}''',
        label="implementasi GetCurrentAPInfo"
    )

    # =========================================================
    # PATCH 4 & 5: ac_u.cpp dan ac_i.cpp
    # =========================================================
    print("=== [4/7] ac_u.cpp - Register GetCurrentAPInfo ===")
    patch(ac_u,
        old='{0x000E, nullptr, "GetCurrentAPInfo"},',
        new='{0x000E, &AC_U::GetCurrentAPInfo, "GetCurrentAPInfo"},',
        label="0x000E ac:u"
    )

    print("=== [5/7] ac_i.cpp - Register GetCurrentAPInfo ===")
    patch(ac_i,
        old='{0x000E, nullptr, "GetCurrentAPInfo"},',
        new='{0x000E, &AC_I::GetCurrentAPInfo, "GetCurrentAPInfo"},',
        label="0x000E ac:i"
    )

    # =========================================================
    # PATCH 6: plgldr.cpp - Fix commit 6d72a6f
    # =========================================================
    print("=== [6/7] plgldr.cpp - Fix commit 6d72a6f ===")
    patch(plg_cpp,
        old='''    FileSys::Plugin3GXLoader plugin_loader;
    if (plgldr_context.use_user_load_parameters &&
        plgldr_context.user_load_parameters.low_title_Id ==
            static_cast<u32>(process.codeset->program_id) &&
        plgldr_context.user_load_parameters.path[0]) {''',
        new='''    FileSys::Plugin3GXLoader plugin_loader;
    const auto low_title_Id = plgldr_context.user_load_parameters.low_title_Id;
    if (plgldr_context.use_user_load_parameters &&
        (low_title_Id == static_cast<u32>(process.codeset->program_id) ||
         low_title_Id == 0 /* Should load for any title */) &&
        plgldr_context.user_load_parameters.path[0]) {''',
        label="fix low_title_Id == 0 (commit 6d72a6f)"
    )

    # =========================================================
    # PATCH 7: plgldr - GetVersion (0x000E)
    # =========================================================
    print("=== [7a/7] plgldr.h - Deklarasi GetVersion ===")
    patch(plg_h,
        old='''    void GetArbiter(Kernel::HLERequestContext& ctx);
    void GetPluginPath(Kernel::HLERequestContext& ctx);''',
        new='''    void GetArbiter(Kernel::HLERequestContext& ctx);
    void GetPluginPath(Kernel::HLERequestContext& ctx);
    void GetVersion(Kernel::HLERequestContext& ctx); // 0x000E''',
        label="deklarasi GetVersion"
    )

    print("=== [7b/7] plgldr.cpp - Register 0x000E GetVersion ===")
    patch(plg_cpp,
        old='''        {0x000D, nullptr, "SetLoadExeParam"},
        // clang-format on
    };''',
        new='''        {0x000D, nullptr, "SetLoadExeParam"},
        {0x000E, &PLG_LDR::GetVersion, "GetVersion"},
        // clang-format on
    };''',
        label="0x000E GetVersion table"
    )

    print("=== [7c/7] plgldr.cpp - Implementasi GetVersion ===")
    patch(plg_cpp,
        old='''void PLG_LDR::GetPluginPath(Kernel::HLERequestContext& ctx) {''',
        new='''void PLG_LDR::GetVersion(Kernel::HLERequestContext& ctx) {
    IPC::RequestParser rp(ctx);

    // Kembalikan versi plgldr (1.0.2)
    // Nimbus 2.0 memanggil 0x000E untuk cek kompatibilitas plugin loader
    IPC::RequestBuilder rb = rp.MakeBuilder(2, 0);
    rb.Push(ResultSuccess);
    rb.Push(plgldr_version.raw);

    LOG_DEBUG(Service_PLGLDR, "GetVersion called, returning {:08X}", plgldr_version.raw);
}

void PLG_LDR::GetPluginPath(Kernel::HLERequestContext& ctx) {''',
        label="implementasi GetVersion"
    )

    print("\n============================")
    print(" Semua patch selesai!")
    print("============================")
    print("\nVerifikasi:")
    print("  git diff src/core/hle/service/ac/ src/core/hle/service/plgldr/")
    print("\nCommit & Push:")
    print("  git add src/core/hle/service/ac/ src/core/hle/service/plgldr/")
    print("  git commit -m 'ac: implement GetCurrentAPInfo stub; plgldr: add GetVersion 0x0E, fix low_title_Id==0'")
    print("  git push")

if __name__ == "__main__":
    main()
