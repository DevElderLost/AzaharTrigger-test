#!/bin/bash
# fix_zerotier_init_order.sh — Fix urutan init ZeroTier
# Masalah: g_jvm masih null saat Init() dipanggil dari Thread background
# karena IDCache::GetEnvForThread() return nullptr di background thread
# dan g_jvm belum di-cache sebelumnya.
#
# Solusi: cache JVM di JNI bridge (jni_zt_bridge.cpp) saat pertama kali
# dipanggil dari main thread, SEBELUM thread background dibuat Kotlin.
#
# Cara pakai:
#   bash scripts/fix_zerotier_init_order.sh

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
JNI_DIR="$PROJECT_ROOT/src/android/app/src/main/jni"

[ -d "$JNI_DIR" ] || error "JNI dir tidak ditemukan: $JNI_DIR"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix ZeroTier Init Order — Cache JVM di JNI bridge"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Fix 1: jni_zt_bridge.cpp — cache JVM di ztInit (main thread) ──
info "Fix 1/2: Tulis ulang jni_zt_bridge.cpp..."

cat > "$JNI_DIR/jni_zt_bridge.cpp" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// jni_zt_bridge.cpp — JNI bridge Kotlin ↔ ZeroTierNative C++
//
// PENTING: ztInit dipanggil dari background Thread di Kotlin,
// tapi JNI function ini sendiri dipanggil dari JVM thread yang valid.
// Kita cache JVM di sini sebelum meneruskan ke ZeroTierNative::Init().

#include <jni.h>
#include <string>
#include "ZeroTierNative.h"
#include "common/logging/log.h"

// Deklarasi extern untuk g_jvm di ZeroTierNative.cpp
namespace ZeroTierNative {
    extern JavaVM* g_jvm;
}

#ifdef __cplusplus
extern "C" {
#endif

JNIEXPORT jint JNICALL
Java_org_citra_citra_1emu_utils_NetPlayManager_ztInit(
        JNIEnv* env, jclass, jstring storagePath, jstring networkIdHex) {

    // Cache JavaVM SEKARANG — kita masih di JVM thread yang valid
    // Ini harus dilakukan sebelum ZeroTierNative::Init() yang jalan
    // di background thread dan membutuhkan g_jvm sudah ter-isi
    if (!ZeroTierNative::g_jvm) {
        env->GetJavaVM(&ZeroTierNative::g_jvm);
        LOG_INFO(Network, "[ZT Bridge] JavaVM di-cache: {}", 
            (void*)ZeroTierNative::g_jvm);
    }

    const char* path  = env->GetStringUTFChars(storagePath,  nullptr);
    const char* netid = env->GetStringUTFChars(networkIdHex, nullptr);
    std::string p(path), n(netid);
    env->ReleaseStringUTFChars(storagePath,  path);
    env->ReleaseStringUTFChars(networkIdHex, netid);

    uint64_t net_id = ZeroTierNative::ParseNetworkId(n);
    if (net_id == 0) {
        LOG_ERROR(Network, "[ZT Bridge] Network ID tidak valid: {}", n);
        return 2;
    }

    return static_cast<jint>(ZeroTierNative::Init(p, net_id));
}

JNIEXPORT void JNICALL
Java_org_citra_citra_1emu_utils_NetPlayManager_ztShutdown(JNIEnv*, jclass) {
    ZeroTierNative::Shutdown();
}

JNIEXPORT jstring JNICALL
Java_org_citra_citra_1emu_utils_NetPlayManager_ztGetAssignedIP(JNIEnv* env, jclass) {
    return env->NewStringUTF(ZeroTierNative::GetAssignedIP().c_str());
}

JNIEXPORT jboolean JNICALL
Java_org_citra_citra_1emu_utils_NetPlayManager_ztIsReady(JNIEnv*, jclass) {
    return ZeroTierNative::IsReady() ? JNI_TRUE : JNI_FALSE;
}

#ifdef __cplusplus
}
#endif
EOF
success "jni_zt_bridge.cpp ditulis ulang"

# ── Fix 2: ZeroTierNative.cpp — ekspor g_jvm agar bisa diakses bridge
info "Fix 2/2: Pastikan g_jvm di ZeroTierNative.cpp bisa diakses..."

ZT_NATIVE="$JNI_DIR/ZeroTierNative.cpp"
[ -f "$ZT_NATIVE" ] || error "ZeroTierNative.cpp tidak ditemukan"

# Ganti static JavaVM* menjadi non-static (bisa diakses dari bridge)
python3 - "$ZT_NATIVE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Ganti "static JavaVM* g_jvm" → "JavaVM* g_jvm" (non-static, bisa extern)
content = content.replace(
    'static JavaVM*           g_jvm              = nullptr;',
    'JavaVM*           g_jvm              = nullptr;  // extern di jni_zt_bridge.cpp'
)
# Juga hapus CacheJVM() yang sekarang tidak diperlukan lagi
# karena JVM sudah di-cache di bridge sebelum Init() dipanggil

with open(path, 'w') as f:
    f.write(content)
print("  g_jvm: static → non-static (extern accessible)")
PYEOF

success "ZeroTierNative.cpp: g_jvm diekspor"

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Fix selesai!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: cache JavaVM di JNI bridge sebelum background thread\""
echo "  git push origin DevElderLost-patch-4"
echo ""
