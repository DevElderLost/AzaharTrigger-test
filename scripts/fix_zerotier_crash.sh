#!/bin/bash
# fix_zerotier_crash.sh — Fix crash saat tombol Hubungkan ditekan
# Root cause: NetPlayManager.ztInit() dipanggil dari background Thread
# tapi JNI native code (ZeroTierNative.cpp) mencoba memanggil
# IDCache::GetEnvForThread() yang butuh thread sudah ter-attach ke JVM.
# Thread yang dibuat manual via Thread{} di Kotlin TIDAK otomatis
# ter-attach ke JVM Android.
#
# Cara pakai:
#   bash scripts/fix_zerotier_crash.sh

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"

JNI_DIR="$PROJECT_ROOT/src/android/app/src/main/jni"
UTILS_DIR="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/utils"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix ZeroTier Crash — Thread JVM Attach + Null Safety"
echo "═══════════════════════════════════════════════════════"
echo ""

# ════════════════════════════════════════════════════════════════════
# FIX 1: ZeroTierNative.cpp — ganti IDCache::GetEnvForThread()
# dengan pendekatan yang attach thread ke JVM secara eksplisit
# ════════════════════════════════════════════════════════════════════
info "Fix 1/2: Tulis ulang ZeroTierNative.cpp — fix JVM thread attach..."

cat > "$JNI_DIR/ZeroTierNative.cpp" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// ZeroTierNative.cpp — Implementasi via libzt AAR Java API
// Fix: attach background thread ke JVM sebelum memanggil Java method
// karena Thread{} di Kotlin tidak otomatis ter-attach ke JVM Android

#include "ZeroTierNative.h"
#include "common/logging/log.h"
#include <atomic>
#include <chrono>
#include <cstring>
#include <string>
#include <thread>
#include <jni.h>

// JavaVM global — di-set saat JNI_OnLoad
static JavaVM* g_jvm = nullptr;

// Dipanggil otomatis oleh Android saat library di-load
JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    g_jvm = vm;
    return JNI_VERSION_1_6;
}

namespace ZeroTierNative {

static std::atomic<bool> zt_initialized{false};
static std::atomic<bool> zt_ready{false};
static char              zt_assigned_ip[64] = {0};
static uint64_t          zt_network_id = 0;
static jclass            g_zt_class    = nullptr;

// ── Helper: attach thread saat ini ke JVM dan ambil JNIEnv ────────
// Thread background (dari Kotlin Thread{}) tidak otomatis ter-attach
// ke JVM, jadi harus di-attach manual sebelum memanggil Java method.
struct ScopedJNIEnv {
    JNIEnv* env   = nullptr;
    bool attached = false;

    ScopedJNIEnv() {
        if (!g_jvm) return;
        jint result = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
        if (result == JNI_EDETACHED) {
            // Thread belum ter-attach, attach sekarang
            JavaVMAttachArgs args{JNI_VERSION_1_6, "ZeroTierThread", nullptr};
            if (g_jvm->AttachCurrentThread(&env, &args) == JNI_OK) {
                attached = true;
            } else {
                env = nullptr;
            }
        } else if (result != JNI_OK) {
            env = nullptr;
        }
    }

    ~ScopedJNIEnv() {
        // Detach hanya jika kita yang attach
        if (attached && g_jvm) {
            g_jvm->DetachCurrentThread();
        }
    }

    bool isValid() const { return env != nullptr; }
};

// ── Pastikan class ZeroTier dari AAR sudah ter-load ───────────────
static bool EnsureClass(JNIEnv* env) {
    if (g_zt_class) return true;
    jclass cls = env->FindClass("com/zerotier/libzt/ZeroTier");
    if (!cls) {
        // Coba nama class alternatif yang mungkin dipakai AAR
        env->ExceptionClear();
        cls = env->FindClass("com/zerotier/sdk/ZeroTier");
        if (!cls) {
            env->ExceptionClear();
            cls = env->FindClass("com/zerotier/libzt/ZeroTierNode");
            if (!cls) {
                env->ExceptionClear();
                LOG_ERROR(Network, "[ZT] Class ZeroTier tidak ditemukan di AAR. "
                    "Periksa nama class yang benar di libzt-release.aar");
                return false;
            }
        }
    }
    g_zt_class = (jclass)env->NewGlobalRef(cls);
    env->DeleteLocalRef(cls);
    return true;
}

// ── Init ──────────────────────────────────────────────────────────
ZTResult Init(const std::string& storage_path, uint64_t network_id) {
    if (zt_initialized) return ZTResult::AlreadyRunning;

    zt_network_id = network_id;
    zt_ready      = false;
    memset(zt_assigned_ip, 0, sizeof(zt_assigned_ip));

    // Attach thread ke JVM
    ScopedJNIEnv scoped;
    if (!scoped.isValid()) {
        LOG_ERROR(Network, "[ZT] Gagal mendapatkan JNIEnv — JVM tidak tersedia");
        return ZTResult::InitFailed;
    }
    JNIEnv* env = scoped.env;

    if (!EnsureClass(env)) return ZTResult::InitFailed;

    // ZeroTier.init(storagePath)
    jmethodID mid_init = env->GetStaticMethodID(
        g_zt_class, "init", "(Ljava/lang/String;)I");
    if (!mid_init) {
        env->ExceptionClear();
        LOG_ERROR(Network, "[ZT] Method init() tidak ditemukan di class ZeroTier");
        return ZTResult::InitFailed;
    }

    jstring jpath  = env->NewStringUTF(storage_path.c_str());
    jint    result = env->CallStaticIntMethod(g_zt_class, mid_init, jpath);
    env->DeleteLocalRef(jpath);
    if (env->ExceptionCheck()) { env->ExceptionClear(); return ZTResult::InitFailed; }
    if (result != 0) {
        LOG_ERROR(Network, "[ZT] init() gagal: {}", (int)result);
        return ZTResult::InitFailed;
    }

    // Tunggu node online (max 15 detik)
    jmethodID mid_online = env->GetStaticMethodID(g_zt_class, "isNodeOnline", "()Z");
    if (!mid_online) { env->ExceptionClear(); }

    constexpr int STEP = 200;
    for (int e = 0; e < 15000 && mid_online; e += STEP) {
        jboolean online = env->CallStaticBooleanMethod(g_zt_class, mid_online);
        if (env->ExceptionCheck()) { env->ExceptionClear(); break; }
        if (online) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(STEP));
    }

    // Cek apakah online
    if (mid_online) {
        jboolean online = env->CallStaticBooleanMethod(g_zt_class, mid_online);
        if (env->ExceptionCheck()) env->ExceptionClear();
        if (!online) {
            LOG_ERROR(Network, "[ZT] Timeout menunggu node online");
            return ZTResult::Timeout;
        }
    }

    // Join network
    jmethodID mid_join = env->GetStaticMethodID(g_zt_class, "join", "(J)I");
    if (!mid_join) {
        env->ExceptionClear();
        LOG_ERROR(Network, "[ZT] Method join() tidak ditemukan");
        return ZTResult::JoinFailed;
    }
    jint join_res = env->CallStaticIntMethod(g_zt_class, mid_join, (jlong)network_id);
    if (env->ExceptionCheck()) { env->ExceptionClear(); return ZTResult::JoinFailed; }
    if (join_res != 0) {
        LOG_ERROR(Network, "[ZT] join() gagal: {}", (int)join_res);
        return ZTResult::JoinFailed;
    }

    // Tunggu IP di-assign (max 20 detik)
    jmethodID mid_ip = env->GetStaticMethodID(
        g_zt_class, "getIPv4Address", "(J)Ljava/lang/String;");
    if (!mid_ip) { env->ExceptionClear(); }

    for (int e = 0; e < 20000 && mid_ip; e += STEP) {
        jstring jip = (jstring)env->CallStaticObjectMethod(
            g_zt_class, mid_ip, (jlong)network_id);
        if (env->ExceptionCheck()) { env->ExceptionClear(); jip = nullptr; }
        if (jip) {
            const char* cip = env->GetStringUTFChars(jip, nullptr);
            if (cip && strlen(cip) > 6) {
                strncpy(zt_assigned_ip, cip, sizeof(zt_assigned_ip) - 1);
                env->ReleaseStringUTFChars(jip, cip);
                env->DeleteLocalRef(jip);
                break;
            }
            if (cip) env->ReleaseStringUTFChars(jip, cip);
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

// ── Shutdown ──────────────────────────────────────────────────────
void Shutdown() {
    if (!zt_initialized) return;

    ScopedJNIEnv scoped;
    if (scoped.isValid() && g_zt_class) {
        JNIEnv* env = scoped.env;
        if (zt_network_id != 0) {
            jmethodID m = env->GetStaticMethodID(g_zt_class, "leave", "(J)I");
            if (m) {
                env->CallStaticIntMethod(g_zt_class, m, (jlong)zt_network_id);
                if (env->ExceptionCheck()) env->ExceptionClear();
            }
        }
        jmethodID m = env->GetStaticMethodID(g_zt_class, "stop", "()I");
        if (m) {
            env->CallStaticIntMethod(g_zt_class, m);
            if (env->ExceptionCheck()) env->ExceptionClear();
        }
    }

    zt_initialized = false;
    zt_ready       = false;
    zt_network_id  = 0;
    memset(zt_assigned_ip, 0, sizeof(zt_assigned_ip));
    LOG_INFO(Network, "[ZT] Shutdown selesai");
}

bool        IsReady()       { return zt_initialized && zt_ready; }
std::string GetAssignedIP() { return std::string(zt_assigned_ip); }
uint64_t    GetNodeID()     { return 0; }

uint64_t ParseNetworkId(const std::string& s) {
    try { return std::stoull(s, nullptr, 16); } catch (...) { return 0; }
}

} // namespace ZeroTierNative
EOF
success "ZeroTierNative.cpp ditulis ulang dengan ScopedJNIEnv"

# ════════════════════════════════════════════════════════════════════
# FIX 2: ZeroTierManager.kt — tambah try-catch dan null safety
# untuk mencegah crash tak tertangani di background thread
# ════════════════════════════════════════════════════════════════════
info "Fix 2/2: Tambah try-catch di ZeroTierManager.kt..."

ZT_MGR="$UTILS_DIR/ZeroTierManager.kt"
[ -f "$ZT_MGR" ] || error "ZeroTierManager.kt tidak ditemukan"

cat > "$ZT_MGR" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
package org.citra.citra_emu.utils

import android.content.Context
import android.util.Log
import java.io.File

object ZeroTierManager {
    private const val TAG       = "ZeroTierManager"
    private const val PREFS_KEY = "zerotier_prefs"
    private const val KEY_NET   = "zt_network_id"

    enum class State { IDLE, STARTING, READY, ERROR }

    @Volatile var state: State = State.IDLE
        private set

    fun saveNetworkId(context: Context, id: String) =
        context.getSharedPreferences(PREFS_KEY, Context.MODE_PRIVATE)
            .edit().putString(KEY_NET, id).apply()

    fun getNetworkId(context: Context): String =
        context.getSharedPreferences(PREFS_KEY, Context.MODE_PRIVATE)
            .getString(KEY_NET, "") ?: ""

    fun hasNetworkId(context: Context) = getNetworkId(context).length == 16

    fun init(
        context: Context,
        networkId: String,
        onReady: (ip: String) -> Unit,
        onError: (msg: String) -> Unit
    ) {
        if (state == State.READY) { onReady(getAssignedIP()); return }
        if (state == State.STARTING) { onError("Sedang dalam proses inisialisasi"); return }
        state = State.STARTING

        val storagePath = try {
            File(context.filesDir, "zt/$networkId").apply { mkdirs() }.absolutePath
        } catch (e: Exception) {
            state = State.ERROR
            onError("Gagal membuat folder storage: ${e.message}")
            return
        }

        Thread {
            try {
                Log.i(TAG, "Init ZeroTier network=$networkId path=$storagePath")
                val code = NetPlayManager.ztInit(storagePath, networkId)
                if (code == 0) {
                    val ip = NetPlayManager.ztGetAssignedIP()
                    if (ip.isNullOrEmpty()) {
                        state = State.ERROR
                        onError("IP tidak diterima dari ZeroTier")
                    } else {
                        state = State.READY
                        Log.i(TAG, "ZeroTier ready IP=$ip")
                        onReady(ip)
                    }
                } else {
                    state = State.ERROR
                    val msg = when (code) {
                        1    -> "Sudah berjalan"
                        2    -> "Gagal inisialisasi — class ZeroTier tidak ditemukan di AAR"
                        3    -> "Gagal join — periksa Network ID"
                        4    -> "Node belum diauthorize di my.zerotier.com"
                        5    -> "Timeout menunggu node online"
                        else -> "Error tidak diketahui (code $code)"
                    }
                    Log.e(TAG, "ZeroTier error: $msg")
                    onError(msg)
                }
            } catch (e: UnsatisfiedLinkError) {
                // Native library tidak ter-load
                state = State.ERROR
                val msg = "Native library ZeroTier tidak ditemukan. Pastikan libzt-release.aar sudah ditambahkan."
                Log.e(TAG, msg, e)
                onError(msg)
            } catch (e: Exception) {
                state = State.ERROR
                val msg = "Crash: ${e.javaClass.simpleName}: ${e.message}"
                Log.e(TAG, msg, e)
                onError(msg)
            }
        }.start()
    }

    fun shutdown() {
        if (state == State.IDLE) return
        try {
            NetPlayManager.ztShutdown()
        } catch (e: Exception) {
            Log.e(TAG, "Shutdown error: ${e.message}", e)
        }
        state = State.IDLE
        Log.i(TAG, "ZeroTier shutdown")
    }

    fun isReady()       = state == State.READY
    fun getAssignedIP() = if (isReady()) NetPlayManager.ztGetAssignedIP() ?: "" else ""
}
EOF
success "ZeroTierManager.kt ditulis ulang dengan try-catch"

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Fix selesai!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Langkah selanjutnya:"
echo "  git add ."
echo "  git commit -m \"fix: ZeroTier crash — ScopedJNIEnv attach thread + try-catch\""
echo "  git push origin DevElderLost-patch-4"
echo ""
