#!/usr/bin/env python3
"""
Patch script untuk AzaharTrigger-test - Pretendo/Nimbus fixes
Dibuat berdasarkan perbandingan file fork vs Official Azahar-emu

Perubahan:
  [ac.h]       - Tambah struct APInfo + deklarasi GetCurrentAPInfo
  [ac.cpp]     - Implementasi GetCurrentAPInfo (dummy data)
  [ac_u.cpp]   - Ganti nullptr -> &AC_U::GetCurrentAPInfo di 0x000E
  [ac_i.cpp]   - Ganti nullptr -> &AC_I::GetCurrentAPInfo di 0x000E
  [plgldr.cpp] - Port fix commit 6d72a6f (low_title_Id == 0 check)
               - Tambah 0x000E GetVersion + implementasi
  [plgldr.h]   - Tambah deklarasi GetVersion

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
    # PATCH 1: ac.h - Tambah struct APInfo
    # Struct ini dibutuhkan oleh GetCurrentAPInfo
    # =========================================================
    print("=== [1/7] ac.h - Tambah struct APInfo ===")
    patch(ac_h,
        old='''    struct ACConfig {
        std::array<u8, 0x200> data;
    };''',
        new='''    struct ACConfig {
        std::array<u8, 0x200> data;
    };

    // APInfo: data access point yang sedang terhubung
    // Dikembalikan oleh GetCurrentAPInfo (command 0x000E)
    // Total size harus 0x34 bytes sesuai protokol 3DS
    struct APInfo {
        std::array<u8, 6> bssid;       // MAC address AP
        std::array<u8, 6> padding1;
        u8 ssid_len;                   // Panjang SSID
        std::array<u8, 32> ssid;       // SSID string (max 32 char)
        u8 padding2;
        u16 channel;                   // WiFi channel
        u8 signal_strength;            // Kekuatan sinyal 0-100
        u8 link_level;                 // Level link 0-3
        std::array<u8, 6> padding3;
        u32 network_id;                // Network ID
    };
    static_assert(sizeof(APInfo) == 0x34, "APInfo size mismatch");''',
        label="struct APInfo"
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
         *      3 : pointer ke buffer output APInfo
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
    # Masukkan sebelum Module::Interface::Interface constructor
    # =========================================================
    print("=== [3/7] ac.cpp - Implementasi GetCurrentAPInfo ===")
    patch(ac_cpp,
        old='''Module::Interface::Interface(std::shared_ptr<Module> ac, const char* name, u32 max_session)
    : ServiceFramework(name, max_session), ac(std::move(ac)) {}''',
        new='''void Module::Interface::GetCurrentAPInfo(Kernel::HLERequestContext& ctx) {
    IPC::RequestParser rp(ctx);
    [[maybe_unused]] u32 size = rp.Pop<u32>();
    auto output_buffer = rp.PopMappedBuffer();

    // Kembalikan data AP dummy agar Nimbus/PIA dapat melanjutkan autentikasi
    // Hardware asli akan mengembalikan data WiFi AP yang sebenarnya
    Module::APInfo ap_info{};
    ap_info.bssid = {0x02, 0x00, 0x00, 0x00, 0x00, 0x01}; // Locally administered MAC
    const char* dummy_ssid = "EmulatorAP";
    ap_info.ssid_len = static_cast<u8>(std::strlen(dummy_ssid));
    std::memcpy(ap_info.ssid.data(), dummy_ssid, ap_info.ssid_len);
    ap_info.channel = 6;
    ap_info.signal_strength = 100;
    ap_info.link_level = 3;
    ap_info.network_id = 1;

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
    # PATCH 4: ac_u.cpp - Ganti nullptr -> handler
    # File fork IDENTIK dengan official - cukup ganti nullptr
    # =========================================================
    print("=== [4/7] ac_u.cpp - Register GetCurrentAPInfo ===")
    patch(ac_u,
        old='{0x000E, nullptr, "GetCurrentAPInfo"},',
        new='{0x000E, &AC_U::GetCurrentAPInfo, "GetCurrentAPInfo"},',
        label="0x000E ac:u"
    )

    # =========================================================
    # PATCH 5: ac_i.cpp - Ganti nullptr -> handler
    # File fork IDENTIK dengan official
    # =========================================================
    print("=== [5/7] ac_i.cpp - Register GetCurrentAPInfo ===")
    patch(ac_i,
        old='{0x000E, nullptr, "GetCurrentAPInfo"},',
        new='{0x000E, &AC_I::GetCurrentAPInfo, "GetCurrentAPInfo"},',
        label="0x000E ac:i"
    )

    # =========================================================
    # PATCH 6: plgldr.cpp - Port fix commit 6d72a6f
    # Fork belum punya fix ini (low_title_Id == 0 check)
    # Official sudah include fix ini dalam file yang diupload
    # Cek dulu apakah fork sudah up-to-date
    # =========================================================
    print("=== [6/7] plgldr.cpp - Port fix commit 6d72a6f ===")
    patch(plg_cpp,
        # Pattern LAMA (sebelum fix 6d72a6f) - tanpa low_title_Id variable
        old='''    FileSys::Plugin3GXLoader plugin_loader;
    if (plgldr_context.use_user_load_parameters &&
        plgldr_context.user_load_parameters.low_title_Id ==
            static_cast<u32>(process.codeset->program_id) &&
        plgldr_context.user_load_parameters.path[0]) {''',
        # Pattern BARU (setelah fix 6d72a6f) - dengan low_title_Id == 0 check
        new='''    FileSys::Plugin3GXLoader plugin_loader;
    const auto low_title_Id = plgldr_context.user_load_parameters.low_title_Id;
    if (plgldr_context.use_user_load_parameters &&
        (low_title_Id == static_cast<u32>(process.codeset->program_id) ||
         low_title_Id == 0 /* Should load for any title */) &&
        plgldr_context.user_load_parameters.path[0]) {''',
        label="fix commit 6d72a6f (low_title_Id == 0)"
    )

    # =========================================================
    # PATCH 7a: plgldr.h - Deklarasi GetVersion (0x000E)
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

    # =========================================================
    # PATCH 7b: plgldr.cpp - Register 0x000E di function table
    # =========================================================
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

    # =========================================================
    # PATCH 7c: plgldr.cpp - Implementasi GetVersion
    # =========================================================
    print("=== [7c/7] plgldr.cpp - Implementasi GetVersion ===")
    patch(plg_cpp,
        old='''void PLG_LDR::GetPluginPath(Kernel::HLERequestContext& ctx) {''',
        new='''void PLG_LDR::GetVersion(Kernel::HLERequestContext& ctx) {
    IPC::RequestParser rp(ctx);

    // Kembalikan versi plgldr (1.0.2) sama seperti GetPLGLDRVersion
    // Nimbus 2.0 memanggil ini (0x000E) untuk cek kompatibilitas plugin loader
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
    print("\nRingkasan perubahan:")
    print("  ac.h      - struct APInfo + deklarasi GetCurrentAPInfo")
    print("  ac.cpp    - implementasi GetCurrentAPInfo (dummy WiFi data)")
    print("  ac_u.cpp  - 0x000E nullptr -> &AC_U::GetCurrentAPInfo")
    print("  ac_i.cpp  - 0x000E nullptr -> &AC_I::GetCurrentAPInfo")
    print("  plgldr.cpp- fix 6d72a6f + GetVersion 0x000E")
    print("  plgldr.h  - deklarasi GetVersion")
    print("\nVerifikasi:")
    print("  git diff src/core/hle/service/ac/ src/core/hle/service/plgldr/")
    print("\nBuild:")
    print("  ./gradlew assembleRelease")

if __name__ == "__main__":
    main()
