#!/usr/bin/env python3
"""
Patch script: Tambah HLE NetworkApplet stub (C502) untuk Pretendo bypass

Steps:
1. Copy network_applet.h/.cpp ke src/core/hle/applets/
2. Register AppletId 0xC502 di applet_manager
3. Tambah ke CMakeLists.txt
4. Include di applet_manager

Usage:
  python3 patch_network_applet.py <repo_root>
"""

import sys, os, shutil

def patch(path, old, new, label):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    if new in content:
        print(f"  [SKIP] '{label}' - sudah ada")
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
        print("Usage: python3 patch_network_applet.py <repo_root>")
        sys.exit(1)

    root = sys.argv[1]
    applets_dir = os.path.join(root, "src/core/hle/applets")
    script_dir  = os.path.dirname(os.path.abspath(__file__))

    # File paths
    network_h   = os.path.join(applets_dir, "network_applet.h")
    network_cpp = os.path.join(applets_dir, "network_applet.cpp")

    # Find applet_manager location
    apt_dir = os.path.join(root, "src/core/hle/service/apt")
    applet_manager_h   = os.path.join(apt_dir, "applet_manager.h")
    applet_manager_cpp = os.path.join(apt_dir, "applet_manager.cpp")

    # Find CMakeLists
    cmake = os.path.join(root, "src/core/CMakeLists.txt")

    for p in [applets_dir, apt_dir]:
        if not os.path.exists(p):
            print(f"[ERROR] Directory tidak ditemukan: {p}")
            sys.exit(1)

    print("[OK] Direktori ditemukan\n")

    # =========================================================
    # STEP 1: Copy network_applet files ke applets dir
    # =========================================================
    print("=== [1/5] Copy network_applet.h dan .cpp ===")

    h_content = '''// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#include "core/hle/applets/applet.h"
#include "core/hle/result.h"

namespace HLE::Applets {

/**
 * NetworkApplet (AppletId 0xC502) - Nintendo Network / Pretendo Network applet stub.
 * This HLE stub immediately closes itself and returns success so games can proceed
 * with online functionality without the actual applet being installed in NAND.
 */
class NetworkApplet final : public Applet {
public:
    explicit NetworkApplet(Core::System& system, Service::APT::AppletId id,
                           Service::APT::AppletId parent, bool preload,
                           std::weak_ptr<Service::APT::AppletManager> manager)
        : Applet(system, id, parent, preload, std::move(manager)) {}

    Result ReceiveParameterImpl(const Service::APT::MessageParameter& parameter) override;
    Result Start(const Service::APT::MessageParameter& parameter) override;
    Result Finalize() override;
    void Update() override;
};

} // namespace HLE::Applets
'''

    cpp_content = '''// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#include "common/logging/log.h"
#include "core/core.h"
#include "core/hle/applets/network_applet.h"
#include "core/hle/service/apt/apt.h"

namespace HLE::Applets {

Result NetworkApplet::ReceiveParameterImpl(const Service::APT::MessageParameter& parameter) {
    LOG_WARNING(Service_APT,
                "NetworkApplet (C502) ReceiveParameterImpl signal={}, stub returning success",
                parameter.signal);

    if (parameter.signal == Service::APT::SignalType::Request) {
        // Send response back to game so it does not hang waiting
        SendParameter({
            .sender_id = id,
            .destination_id = parent,
            .signal = Service::APT::SignalType::Response,
            .object = nullptr,
            .buffer = {},
        });
    }

    return ResultSuccess;
}

Result NetworkApplet::Start(const Service::APT::MessageParameter& parameter) {
    LOG_WARNING(Service_APT,
                "NetworkApplet (C502) Start - stub immediately closing applet");
    Finalize();
    return ResultSuccess;
}

Result NetworkApplet::Finalize() {
    LOG_WARNING(Service_APT, "NetworkApplet (C502) Finalize - closing stub applet");
    CloseApplet(nullptr, {});
    return ResultSuccess;
}

void NetworkApplet::Update() {}

} // namespace HLE::Applets
'''

    with open(network_h, 'w') as f:
        f.write(h_content)
    print(f"  [OK] {network_h}")

    with open(network_cpp, 'w') as f:
        f.write(cpp_content)
    print(f"  [OK] {network_cpp}")

    # =========================================================
    # STEP 2: Register di AppletId enum (applet_manager.h)
    # Tambah NetworkApplet = 0xC502 setelah AmiboSettings
    # =========================================================
    print("\n=== [2/5] applet_manager.h - Tambah AppletId NetworkApplet ===")
    patch(applet_manager_h,
        old='    AmiboSettings = 0x119,',
        new='''    AmiboSettings = 0x119,
    NetworkApplet = 0xC502, ///< Nintendo Network / Pretendo Network applet''',
        label="AppletId::NetworkApplet"
    )

    # =========================================================
    # STEP 3: Register di applet_manager.cpp - tabel applet
    # =========================================================
    print("\n=== [3/5] applet_manager.cpp - Register NetworkApplet ===")

    # Cari pattern tabel registrasi
    with open(applet_manager_cpp, 'r') as f:
        mgr_content = f.read()

    # Cari include section untuk tambah include network_applet.h
    if '#include "core/hle/applets/erreula.h"' in mgr_content:
        patch(applet_manager_cpp,
            old='#include "core/hle/applets/erreula.h"',
            new='#include "core/hle/applets/erreula.h"\n#include "core/hle/applets/network_applet.h"',
            label="include network_applet.h"
        )
    elif '#include "core/hle/applets/' in mgr_content:
        # Cari include applet apapun dan tambah setelahnya
        lines = mgr_content.split('\n')
        last_applet_include = -1
        for i, line in enumerate(lines):
            if '#include "core/hle/applets/' in line:
                last_applet_include = i
        if last_applet_include >= 0:
            lines.insert(last_applet_include + 1, '#include "core/hle/applets/network_applet.h"')
            with open(applet_manager_cpp, 'w') as f:
                f.write('\n'.join(lines))
            print("  [OK] include network_applet.h ditambahkan")
    else:
        print("  [INFO] Tidak bisa auto-add include, tambah manual:")
        print('         #include "core/hle/applets/network_applet.h"')

    # Cari tabel Create/Register applet dan tambah NetworkApplet
    with open(applet_manager_cpp, 'r') as f:
        mgr_content = f.read()

    # Pattern tabel yang biasa ada: {AppletId::AmiboSettings, ...}
    if '{AppletId::AmiboSettings,' in mgr_content:
        patch(applet_manager_cpp,
            old='{AppletId::AmiboSettings,',
            new='{AppletId::NetworkApplet, [](...) { return std::make_shared<HLE::Applets::NetworkApplet>(...); }},\n        {AppletId::AmiboSettings,',
            label="NetworkApplet in table (AmiboSettings pattern)"
        )
    else:
        # Cari pola lain - ErrEula
        if 'AppletId::Error' in mgr_content and 'ErrEula' in mgr_content:
            patch(applet_manager_cpp,
                old='{AppletId::Error,',
                new='{AppletId::NetworkApplet, [](...) { return std::make_shared<HLE::Applets::NetworkApplet>(...); }},\n        {AppletId::Error,',
                label="NetworkApplet in table (Error pattern)"
            )
        else:
            print("  [INFO] Tidak bisa auto-register, perlu cek manual pola tabel di applet_manager.cpp")
            print("         Cari tabel applet dan tambah entry NetworkApplet")

    # =========================================================
    # STEP 4: Tambah ke CMakeLists.txt
    # =========================================================
    print("\n=== [4/5] CMakeLists.txt - Tambah network_applet files ===")
    if os.path.exists(cmake):
        patch(cmake,
            old='hle/applets/erreula.cpp\n    hle/applets/erreula.h',
            new='hle/applets/erreula.cpp\n    hle/applets/erreula.h\n    hle/applets/network_applet.cpp\n    hle/applets/network_applet.h',
            label="network_applet in CMakeLists"
        )
    else:
        print(f"  [INFO] {cmake} tidak ditemukan, cari CMakeLists yang benar")

    print("\n============================")
    print(" Selesai!")
    print("============================")
    print("\nJika step 3 MISS, jalankan:")
    print("  grep -n 'AppletId::Error\\|ErrEula\\|applet_ids\\|Create' \\")
    print("    src/core/hle/service/apt/applet_manager.cpp | head -30")
    print("\nVerifikasi:")
    print("  git diff src/core/hle/")
    print("\nCommit:")
    print("  git add src/core/hle/")
    print("  git commit -m 'applets: add NetworkApplet HLE stub for C502 Pretendo bypass'")
    print("  git push")

if __name__ == "__main__":
    main()
