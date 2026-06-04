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
