#!/bin/bash
# fix_jni_onload.sh — Fix duplicate JNI_OnLoad
# Hapus JNI_OnLoad dari ZeroTierNative.cpp, gunakan IDCache
#
# Cara pakai:
#   bash scripts/fix_jni_onload.sh

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
JNI_DIR="$PROJECT_ROOT/src/android/app/src/main/jni"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix: duplicate JNI_OnLoad"
echo "═══════════════════════════════════════════════════════"
echo ""

# Cek id_cache.cpp untuk lihat bagaimana JavaVM disimpan
ID_CACHE_CPP=$(find "$PROJECT_ROOT/src" -name "id_cache.cpp" | head -1)
if [ -n "$ID_CACHE_CPP" ]; then
    info "JavaVM di id_cache.cpp:"
    grep -n "JavaVM\|g_jvm\|s_jvm\|GetJVM\|JNI_OnLoad" "$ID_CACHE_CPP" | head -10
fi

echo ""
info "Tulis ulang ZeroTierNative.cpp tanpa JNI_OnLoad..."

ZT_NATIVE="$JNI_DIR/ZeroTierNative.cpp"
[ -f "$ZT_NATIVE" ] || error "ZeroTierNative.cpp tidak ditemukan: $ZT_NATIVE"

# Tulis file baru ke /tmp dulu lalu pindahkan
cat > /tmp/ZeroTierNative_new.cpp << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// ZeroTierNative.cpp — implementasi via libzt AAR Java API
//
// TIDAK mendefinisikan JNI_OnLoad — sudah ada di id_cache.cpp
// JavaVM diambil dari env->GetJavaVM() saat pertama kali dipanggil

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
static uint64_t          zt_network_id      = 0;
static jclass            g_zt_class         = nullptr;
static JavaVM*           g_jvm              = nullptr;

// ── Simpan JavaVM dari env yang valid ────────────────────────────
static void CacheJVM(JNIEnv* env) {
    if (!g_jvm && env) {
        env->GetJavaVM(&g_jvm);
    }
}

// ── Attach thread background ke JVM ──────────────────────────────
struct ScopedJNIEnv {
    JNIEnv* env      = nullptr;
    bool    attached = false;

    ScopedJNIEnv() {
        if (!g_jvm) return;
        jint res = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
        if (res == JNI_EDETACHED) {
            JavaVMAttachArgs args{JNI_VERSION_1_6, "ZeroTierNative", nullptr};
            if (g_jvm->AttachCurrentThread(&env, &args) == JNI_OK) {
                attached = true;
            } else {
                env = nullptr;
            }
        } else if (res != JNI_OK) {
            env = nullptr;
        }
    }

    ~ScopedJNIEnv() {
        if (attached && g_jvm) g_jvm->DetachCurrentThread();
    }

    bool isValid() const { return env != nullptr; }
};

// ── Temukan class ZeroTier dari AAR ──────────────────────────────
static bool EnsureClass(JNIEnv* env) {
    if (g_zt_class) return true;
    const char* candidates[] = {
        "com/zerotier/libzt/ZeroTier",
        "com/zerotier/sdk/ZeroTier",
        "com/zerotier/libzt/ZeroTierNode",
        nullptr
    };
    for (int i = 0; candidates[i]; i++) {
        jclass cls = env->FindClass(candidates[i]);
        if (cls && !env->ExceptionCheck()) {
            g_zt_class = (jclass)env->NewGlobalRef(cls);
            env->DeleteLocalRef(cls);
            LOG_INFO(Network, "[ZT] Class: {}", candidates[i]);
            return true;
        }
        env->ExceptionClear();
    }
    LOG_ERROR(Network, "[ZT] Class ZeroTier tidak ditemukan di AAR");
    return false;
}

// ── Init — dipanggil dari jni_zt_bridge.cpp di main thread ───────
ZTResult Init(const std::string& storage_path, uint64_t network_id) {
    if (zt_initialized) return ZTResult::AlreadyRunning;

    zt_network_id = network_id;
    zt_ready      = false;
    memset(zt_assigned_ip, 0, sizeof(zt_assigned_ip));

    // Pertama coba IDCache (sudah ter-attach ke JVM)
    JNIEnv* main_env = IDCache::GetEnvForThread();
    if (main_env) {
        CacheJVM(main_env); // simpan JavaVM untuk thread berikutnya
    }

    ScopedJNIEnv scoped;
    if (!scoped.isValid()) {
        LOG_ERROR(Network, "[ZT] JNIEnv tidak tersedia");
        return ZTResult::InitFailed;
    }
    JNIEnv* env = scoped.env;
    CacheJVM(env);

    if (!EnsureClass(env)) return ZTResult::InitFailed;

    // init(storagePath)
    jmethodID mid_init = env->GetStaticMethodID(
        g_zt_class, "init", "(Ljava/lang/String;)I");
    if (!mid_init) { env->ExceptionClear(); return ZTResult::InitFailed; }
    jstring jpath = env->NewStringUTF(storage_path.c_str());
    jint res = env->CallStaticIntMethod(g_zt_class, mid_init, jpath);
    env->DeleteLocalRef(jpath);
    if (env->ExceptionCheck()) { env->ExceptionClear(); return ZTResult::InitFailed; }
    if (res != 0) return ZTResult::InitFailed;

    // Tunggu node online (15s)
    constexpr int STEP = 200;
    jmethodID mid_on = env->GetStaticMethodID(g_zt_class, "isNodeOnline", "()Z");
    if (!mid_on) env->ExceptionClear();
    for (int e = 0; e < 15000 && mid_on; e += STEP) {
        jboolean on = env->CallStaticBooleanMethod(g_zt_class, mid_on);
        if (env->ExceptionCheck()) { env->ExceptionClear(); break; }
        if (on) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(STEP));
    }
    if (mid_on) {
        jboolean on = env->CallStaticBooleanMethod(g_zt_class, mid_on);
        if (env->ExceptionCheck()) env->ExceptionClear();
        else if (!on) return ZTResult::Timeout;
    }

    // Join network
    jmethodID mid_join = env->GetStaticMethodID(g_zt_class, "join", "(J)I");
    if (!mid_join) { env->ExceptionClear(); return ZTResult::JoinFailed; }
    jint jr = env->CallStaticIntMethod(g_zt_class, mid_join, (jlong)network_id);
    if (env->ExceptionCheck()) { env->ExceptionClear(); return ZTResult::JoinFailed; }
    if (jr != 0) return ZTResult::JoinFailed;

    // Tunggu IP (20s)
    jmethodID mid_ip = env->GetStaticMethodID(
        g_zt_class, "getIPv4Address", "(J)Ljava/lang/String;");
    if (!mid_ip) env->ExceptionClear();
    for (int e = 0; e < 20000 && mid_ip; e += STEP) {
        jstring jip = (jstring)env->CallStaticObjectMethod(
            g_zt_class, mid_ip, (jlong)network_id);
        if (env->ExceptionCheck()) { env->ExceptionClear(); jip = nullptr; }
        if (jip) {
            const char* c = env->GetStringUTFChars(jip, nullptr);
            if (c && strlen(c) > 6) {
                strncpy(zt_assigned_ip, c, sizeof(zt_assigned_ip) - 1);
                env->ReleaseStringUTFChars(jip, c);
                env->DeleteLocalRef(jip);
                break;
            }
            if (c) env->ReleaseStringUTFChars(jip, c);
            env->DeleteLocalRef(jip);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(STEP));
    }
    if (strlen(zt_assigned_ip) == 0) return ZTResult::NetworkNotReady;

    LOG_INFO(Network, "[ZT] Siap! IP: {}", zt_assigned_ip);
    zt_initialized = true;
    zt_ready       = true;
    return ZTResult::OK;
}

void Shutdown() {
    if (!zt_initialized) return;
    ScopedJNIEnv scoped;
    if (scoped.isValid() && g_zt_class) {
        JNIEnv* env = scoped.env;
        if (zt_network_id != 0) {
            jmethodID m = env->GetStaticMethodID(g_zt_class, "leave", "(J)I");
            if (m) { env->CallStaticIntMethod(g_zt_class, m, (jlong)zt_network_id); env->ExceptionClear(); }
        }
        jmethodID m = env->GetStaticMethodID(g_zt_class, "stop", "()I");
        if (m) { env->CallStaticIntMethod(g_zt_class, m); env->ExceptionClear(); }
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

cp /tmp/ZeroTierNative_new.cpp "$ZT_NATIVE"
success "ZeroTierNative.cpp ditulis ulang tanpa JNI_OnLoad"

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Fix selesai!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: hapus JNI_OnLoad duplikat dari ZeroTierNative.cpp\""
echo "  git push origin DevElderLost-patch-4"
echo ""
