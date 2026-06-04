// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// ZeroTierNative.cpp — menggunakan com.zerotier.sockets.ZeroTierNode
// dari libzt-release.aar
//
// API ZeroTierNode (libzt Android AAR):
//   ZeroTierNode node = new ZeroTierNode();
//   node.init(storagePath, port)  → mulai node
//   node.start()                  → start service
//   node.isOnline()               → cek online
//   node.join(networkId)          → join network
//   node.getIPV4Address(networkId) → ambil IP
//   node.stop()                   → stop

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
JavaVM*           g_jvm              = nullptr;  // extern di jni_zt_bridge.cpp

// Instance ZeroTierNode (object, bukan static class)
static jobject g_node_instance = nullptr;
static jclass  g_node_class    = nullptr;

// ── Cache JavaVM ──────────────────────────────────────────────────
static void CacheJVM(JNIEnv* env) {
    if (!g_jvm && env) env->GetJavaVM(&g_jvm);
}

// ── Attach thread ke JVM ─────────────────────────────────────────
struct ScopedJNIEnv {
    JNIEnv* env      = nullptr;
    bool    attached = false;

    ScopedJNIEnv() {
        // Coba dari IDCache dulu (main thread)
        env = IDCache::GetEnvForThread();
        if (env) return;
        // Attach manual jika background thread
        if (!g_jvm) return;
        jint res = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
        if (res == JNI_EDETACHED) {
            JavaVMAttachArgs args{JNI_VERSION_1_6, "ZeroTierNative", nullptr};
            if (g_jvm->AttachCurrentThread(&env, &args) == JNI_OK)
                attached = true;
            else
                env = nullptr;
        } else if (res != JNI_OK) {
            env = nullptr;
        }
    }
    ~ScopedJNIEnv() {
        if (attached && g_jvm) g_jvm->DetachCurrentThread();
    }
    bool isValid() const { return env != nullptr; }
};

// ── Buat instance ZeroTierNode ────────────────────────────────────
static bool CreateNodeInstance(JNIEnv* env) {
    if (g_node_instance) return true;

    g_node_class = env->FindClass("com/zerotier/sockets/ZeroTierNode");
    if (!g_node_class || env->ExceptionCheck()) {
        env->ExceptionClear();
        LOG_ERROR(Network, "[ZT] Class com/zerotier/sockets/ZeroTierNode tidak ditemukan");
        return false;
    }
    g_node_class = (jclass)env->NewGlobalRef(g_node_class);

    // Buat instance: new ZeroTierNode()
    jmethodID ctor = env->GetMethodID(g_node_class, "<init>", "()V");
    if (!ctor || env->ExceptionCheck()) {
        env->ExceptionClear();
        LOG_ERROR(Network, "[ZT] Constructor ZeroTierNode() tidak ditemukan");
        return false;
    }

    jobject local = env->NewObject(g_node_class, ctor);
    if (!local || env->ExceptionCheck()) {
        env->ExceptionClear();
        LOG_ERROR(Network, "[ZT] Gagal membuat instance ZeroTierNode");
        return false;
    }

    g_node_instance = env->NewGlobalRef(local);
    env->DeleteLocalRef(local);
    LOG_INFO(Network, "[ZT] ZeroTierNode instance dibuat");
    return true;
}

// ── Helper: panggil method void di node instance ──────────────────
static bool CallVoidMethod(JNIEnv* env, const char* name, const char* sig, ...) {
    jmethodID m = env->GetMethodID(g_node_class, name, sig);
    if (!m || env->ExceptionCheck()) { env->ExceptionClear(); return false; }
    va_list args; va_start(args, sig);
    // Untuk simplisitas, panggil tanpa vararg (handle case by case)
    va_end(args);
    return true;
}

// ── Init ──────────────────────────────────────────────────────────
ZTResult Init(const std::string& storage_path, uint64_t network_id) {
    if (zt_initialized) return ZTResult::AlreadyRunning;

    zt_network_id = network_id;
    zt_ready      = false;
    memset(zt_assigned_ip, 0, sizeof(zt_assigned_ip));

    ScopedJNIEnv scoped;
    if (!scoped.isValid()) return ZTResult::InitFailed;
    JNIEnv* env = scoped.env;
    CacheJVM(env);

    if (!CreateNodeInstance(env)) return ZTResult::InitFailed;

    constexpr int STEP = 200;

    // node.init(storagePath, port=9994)
    jmethodID mid_init = env->GetMethodID(g_node_class, "init",
        "(Ljava/lang/String;I)V");
    if (!mid_init || env->ExceptionCheck()) {
        env->ExceptionClear();
        // Coba signature tanpa port
        mid_init = env->GetMethodID(g_node_class, "init",
            "(Ljava/lang/String;)V");
    }
    if (!mid_init || env->ExceptionCheck()) {
        env->ExceptionClear();
        LOG_ERROR(Network, "[ZT] Method init() tidak ditemukan");
        return ZTResult::InitFailed;
    }
    jstring jpath = env->NewStringUTF(storage_path.c_str());

    // Coba panggil init(path, port)
    jmethodID mid_init_port = env->GetMethodID(g_node_class, "init",
        "(Ljava/lang/String;I)V");
    if (mid_init_port && !env->ExceptionCheck()) {
        env->CallVoidMethod(g_node_instance, mid_init_port, jpath, (jint)9994);
    } else {
        env->ExceptionClear();
        env->CallVoidMethod(g_node_instance, mid_init, jpath);
    }
    env->DeleteLocalRef(jpath);
    if (env->ExceptionCheck()) { env->ExceptionClear(); return ZTResult::InitFailed; }

    // node.start()
    jmethodID mid_start = env->GetMethodID(g_node_class, "start", "()V");
    if (mid_start && !env->ExceptionCheck()) {
        env->CallVoidMethod(g_node_instance, mid_start);
        if (env->ExceptionCheck()) env->ExceptionClear();
    } else {
        env->ExceptionClear();
    }

    // Tunggu node online: node.isOnline() (15s)
    jmethodID mid_online = env->GetMethodID(g_node_class, "isOnline", "()Z");
    if (!mid_online) { env->ExceptionClear(); mid_online = env->GetMethodID(g_node_class, "online", "()Z"); }
    if (!mid_online) env->ExceptionClear();

    for (int e = 0; e < 15000 && mid_online; e += STEP) {
        jboolean on = env->CallBooleanMethod(g_node_instance, mid_online);
        if (env->ExceptionCheck()) { env->ExceptionClear(); break; }
        if (on) { LOG_INFO(Network, "[ZT] Node online"); break; }
        std::this_thread::sleep_for(std::chrono::milliseconds(STEP));
    }

    // node.join(networkId)
    jmethodID mid_join = env->GetMethodID(g_node_class, "join", "(J)V");
    if (!mid_join || env->ExceptionCheck()) {
        env->ExceptionClear();
        mid_join = env->GetMethodID(g_node_class, "joinNetwork", "(J)V");
    }
    if (!mid_join || env->ExceptionCheck()) {
        env->ExceptionClear();
        LOG_ERROR(Network, "[ZT] Method join() tidak ditemukan");
        return ZTResult::JoinFailed;
    }
    env->CallVoidMethod(g_node_instance, mid_join, (jlong)network_id);
    if (env->ExceptionCheck()) { env->ExceptionClear(); return ZTResult::JoinFailed; }

    // Tunggu IP: node.getIPV4Address(networkId) (20s)
    jmethodID mid_ip = env->GetMethodID(g_node_class, "getIPV4Address",
        "(J)Ljava/lang/String;");
    if (!mid_ip || env->ExceptionCheck()) {
        env->ExceptionClear();
        mid_ip = env->GetMethodID(g_node_class, "getIPv4Address",
            "(J)Ljava/lang/String;");
    }
    if (!mid_ip) env->ExceptionClear();

    for (int e = 0; e < 20000 && mid_ip; e += STEP) {
        jstring jip = (jstring)env->CallObjectMethod(
            g_node_instance, mid_ip, (jlong)network_id);
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

    if (strlen(zt_assigned_ip) == 0) {
        LOG_ERROR(Network, "[ZT] Timeout IP — authorize node di my.zerotier.com");
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
    if (scoped.isValid() && g_node_instance && g_node_class) {
        JNIEnv* env = scoped.env;

        // node.leave(networkId)
        if (zt_network_id != 0) {
            jmethodID m = env->GetMethodID(g_node_class, "leave", "(J)V");
            if (!m) { env->ExceptionClear();
                m = env->GetMethodID(g_node_class, "leaveNetwork", "(J)V"); }
            if (m) {
                env->CallVoidMethod(g_node_instance, m, (jlong)zt_network_id);
                if (env->ExceptionCheck()) env->ExceptionClear();
            } else env->ExceptionClear();
        }

        // node.stop()
        jmethodID m = env->GetMethodID(g_node_class, "stop", "()V");
        if (m) {
            env->CallVoidMethod(g_node_instance, m);
            if (env->ExceptionCheck()) env->ExceptionClear();
        } else env->ExceptionClear();

        env->DeleteGlobalRef(g_node_instance);
        g_node_instance = nullptr;
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
uint64_t    ParseNetworkId(const std::string& s) {
    try { return std::stoull(s, nullptr, 16); } catch (...) { return 0; }
}

} // namespace ZeroTierNative
