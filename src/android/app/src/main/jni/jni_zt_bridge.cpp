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
