#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# fix_zerotier_errors.sh — Fix 2 error build ZeroTier
#
# Error 1: ZeroTierSockets.h not found
# Error 2: ZeroTierInit/Shutdown/GetIP/IsReady tidak ada di multiplayer.h
#
# Cara pakai:
#   bash scripts/fix_zerotier_errors.sh
# ═══════════════════════════════════════════════════════════════════

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
JNI_DIR="$PROJECT_ROOT/src/android/app/src/main/jni"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix ZeroTier Build Errors — AzaharTrigger"
echo "═══════════════════════════════════════════════════════"
echo ""

# ════════════════════════════════════════════════════════════════════
# FIX 1: ZeroTierNative.h — hapus ZeroTierSockets.h, pakai JNI saja
# ════════════════════════════════════════════════════════════════════
info "Fix 1/3: Tulis ulang ZeroTierNative.h..."

cat > "$JNI_DIR/ZeroTierNative.h" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// ZeroTierNative.h — wrapper libzt via AAR Java API
// Tidak memerlukan ZeroTierSockets.h (tidak ada header C dari AAR)
// Semua operasi ZeroTier dipanggil via JNI ke Java class di AAR

#pragma once
#include <cstdint>
#include <string>

namespace ZeroTierNative {

enum class ZTResult {
    OK = 0,
    AlreadyRunning,
    InitFailed,
    JoinFailed,
    NetworkNotReady,
    Timeout,
};

/**
 * Inisialisasi ZeroTier via AAR Java API.
 * Memanggil com.zerotier.libzt.ZeroTier melalui JNI.
 */
ZTResult    Init(const std::string& storage_path, uint64_t network_id);
void        Shutdown();
bool        IsReady();
std::string GetAssignedIP();
uint64_t    GetNodeID();
uint64_t    ParseNetworkId(const std::string& hex_str);

} // namespace ZeroTierNative
EOF
success "ZeroTierNative.h ditulis ulang (tanpa ZeroTierSockets.h)"

# ════════════════════════════════════════════════════════════════════
# FIX 2: ZeroTierNative.cpp — hapus include ZeroTierSockets.h
# ════════════════════════════════════════════════════════════════════
info "Fix 2/3: Tulis ulang ZeroTierNative.cpp..."

cat > "$JNI_DIR/ZeroTierNative.cpp" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// ZeroTierNative.cpp — Implementasi via libzt AAR Java API
// Tidak ada #include <ZeroTierSockets.h> karena AAR tidak expose header C
// Semua operasi ZeroTier dipanggil via JNI ke Java class di AAR:
//   com.zerotier.libzt.ZeroTier

#include "ZeroTierNative.h"
#include "common/logging/log.h"
#include "jni/id_cache.h"
#include <atomic>
#include <chrono>
#include <cstring>
#include <string>
#include <thread>
#include <jni.h>

namespace ZeroTierNative {

static std::atomic<bool> zt_initialized{false};
static std::atomic<bool> zt_ready{false};
static char              zt_assigned_ip[64] = {0};
static uint64_t          zt_network_id = 0;
static jclass            g_zt_class    = nullptr;

static bool EnsureClass(JNIEnv* env) {
    if (g_zt_class) return true;
    jclass cls = env->FindClass("com/zerotier/libzt/ZeroTier");
    if (!cls) {
        LOG_ERROR(Network, "[ZT] Class com/zerotier/libzt/ZeroTier tidak ditemukan di AAR");
        return false;
    }
    g_zt_class = (jclass)env->NewGlobalRef(cls);
    env->DeleteLocalRef(cls);
    return true;
}

ZTResult Init(const std::string& storage_path, uint64_t network_id) {
    if (zt_initialized) return ZTResult::AlreadyRunning;

    zt_network_id = network_id;
    zt_ready      = false;
    memset(zt_assigned_ip, 0, sizeof(zt_assigned_ip));

    JNIEnv* env = IDCache::GetEnvForThread();
    if (!env)                  return ZTResult::InitFailed;
    if (!EnsureClass(env))     return ZTResult::InitFailed;

    // Panggil ZeroTier.init(storagePath)
    jmethodID mid_init = env->GetStaticMethodID(
        g_zt_class, "init", "(Ljava/lang/String;)I");
    if (!mid_init) {
        LOG_ERROR(Network, "[ZT] Method ZeroTier.init() tidak ditemukan");
        return ZTResult::InitFailed;
    }
    jstring jpath  = env->NewStringUTF(storage_path.c_str());
    jint    result = env->CallStaticIntMethod(g_zt_class, mid_init, jpath);
    env->DeleteLocalRef(jpath);
    if (result != 0) {
        LOG_ERROR(Network, "[ZT] ZeroTier.init() gagal: {}", (int)result);
        return ZTResult::InitFailed;
    }

    // Tunggu node online (max 15 detik)
    jmethodID mid_online = env->GetStaticMethodID(g_zt_class, "isNodeOnline", "()Z");
    constexpr int STEP = 200;
    for (int e = 0; e < 15000 && mid_online; e += STEP) {
        if (env->CallStaticBooleanMethod(g_zt_class, mid_online)) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(STEP));
    }
    if (!mid_online || !env->CallStaticBooleanMethod(g_zt_class, mid_online)) {
        LOG_ERROR(Network, "[ZT] Timeout menunggu node online");
        return ZTResult::Timeout;
    }

    // Join network
    jmethodID mid_join = env->GetStaticMethodID(g_zt_class, "join", "(J)I");
    if (!mid_join) return ZTResult::JoinFailed;
    if (env->CallStaticIntMethod(g_zt_class, mid_join, (jlong)network_id) != 0)
        return ZTResult::JoinFailed;

    // Tunggu IP di-assign (max 20 detik)
    jmethodID mid_ip = env->GetStaticMethodID(
        g_zt_class, "getIPv4Address", "(J)Ljava/lang/String;");
    for (int e = 0; e < 20000 && mid_ip; e += STEP) {
        jstring jip = (jstring)env->CallStaticObjectMethod(
            g_zt_class, mid_ip, (jlong)network_id);
        if (jip) {
            const char* cip = env->GetStringUTFChars(jip, nullptr);
            if (cip && strlen(cip) > 6) {
                strncpy(zt_assigned_ip, cip, sizeof(zt_assigned_ip) - 1);
                env->ReleaseStringUTFChars(jip, cip);
                env->DeleteLocalRef(jip);
                break;
            }
            env->ReleaseStringUTFChars(jip, cip);
            env->DeleteLocalRef(jip);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(STEP));
    }

    if (strlen(zt_assigned_ip) == 0) {
        LOG_ERROR(Network, "[ZT] Timeout IP — pastikan node sudah diauthorize");
        return ZTResult::NetworkNotReady;
    }

    LOG_INFO(Network, "[ZT] Siap! IP: {}", zt_assigned_ip);
    zt_initialized = true;
    zt_ready       = true;
    return ZTResult::OK;
}

void Shutdown() {
    if (!zt_initialized) return;
    JNIEnv* env = IDCache::GetEnvForThread();
    if (env && g_zt_class) {
        if (zt_network_id != 0) {
            jmethodID m = env->GetStaticMethodID(g_zt_class, "leave", "(J)I");
            if (m) env->CallStaticIntMethod(g_zt_class, m, (jlong)zt_network_id);
        }
        jmethodID m = env->GetStaticMethodID(g_zt_class, "stop", "()I");
        if (m) env->CallStaticIntMethod(g_zt_class, m);
    }
    zt_initialized = false;
    zt_ready       = false;
    zt_network_id  = 0;
    memset(zt_assigned_ip, 0, sizeof(zt_assigned_ip));
}

bool        IsReady()       { return zt_initialized && zt_ready; }
std::string GetAssignedIP() { return std::string(zt_assigned_ip); }
uint64_t    GetNodeID()     { return 0; }
uint64_t    ParseNetworkId(const std::string& s) {
    try { return std::stoull(s, nullptr, 16); } catch (...) { return 0; }
}

} // namespace ZeroTierNative
EOF
success "ZeroTierNative.cpp ditulis ulang"

# ════════════════════════════════════════════════════════════════════
# FIX 3: multiplayer.h — tambah deklarasi 4 fungsi ZeroTier
# ════════════════════════════════════════════════════════════════════
info "Fix 3/3: Tambah deklarasi ZeroTier ke multiplayer.h..."

MULTI_H=$(find "$JNI_DIR" -name "multiplayer.h" 2>/dev/null | head -1)
if [ -z "$MULTI_H" ]; then
    MULTI_H=$(find "$PROJECT_ROOT/src" -name "multiplayer.h" 2>/dev/null | head -1)
fi
[ -n "$MULTI_H" ] || error "multiplayer.h tidak ditemukan"
info "multiplayer.h: $MULTI_H"

if ! grep -q "ZeroTierInit" "$MULTI_H"; then
    cp "$MULTI_H" "${MULTI_H}.bak"

    # Tulis python ke temp file
    PATCH_PY=$(mktemp /tmp/patch_header_XXXXXX.py)
    cat > "$PATCH_PY" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

zt_decl = """
    // ── ZeroTier native tunnel (via libzt AAR) ─────────────────────
    // Dipanggil dari Kotlin ZeroTierManager via JNI (NetPlayManager)
    NetPlayStatus ZeroTierInit(const std::string& storage_path,
                               const std::string& network_id_hex);
    void          ZeroTierShutdown();
    std::string   ZeroTierGetIP();
    bool          ZeroTierIsReady();
"""

# Sisipkan sebelum closing brace class AndroidMultiplayer
# Cari tanda akhir class: '};' terakhir
last = content.rfind('};')
if last != -1:
    content = content[:last] + zt_decl + content[last:]
    with open(path, 'w') as f:
        f.write(content)
    print("  4 deklarasi ZeroTier ditambahkan ke multiplayer.h")
else:
    print("  WARN: closing brace '};' tidak ditemukan di multiplayer.h")
PYEOF

    python3 "$PATCH_PY" "$MULTI_H"
    rm -f "$PATCH_PY"
    success "multiplayer.h: tambah deklarasi ZeroTierInit/Shutdown/GetIP/IsReady"
else
    warn "multiplayer.h: deklarasi ZeroTier sudah ada, skip"
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Fix selesai!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Langkah selanjutnya:"
echo "  git add ."
echo "  git commit -m \"fix: ZeroTierNative no ZeroTierSockets.h + tambah deklarasi di multiplayer.h\""
echo "  git push origin DevElderLost-patch-4"
echo ""
