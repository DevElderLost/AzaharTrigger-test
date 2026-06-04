// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
#include <jni.h>
#include <string>
#include "ZeroTierNative.h"

#ifdef __cplusplus
extern "C" {
#endif

JNIEXPORT jint JNICALL
Java_org_citra_citra_1emu_utils_NetPlayManager_ztInit(
        JNIEnv* env, jclass, jstring storagePath, jstring networkIdHex) {
    const char* path  = env->GetStringUTFChars(storagePath,  nullptr);
    const char* netid = env->GetStringUTFChars(networkIdHex, nullptr);
    std::string p(path), n(netid);
    env->ReleaseStringUTFChars(storagePath,  path);
    env->ReleaseStringUTFChars(networkIdHex, netid);
    uint64_t net_id = ZeroTierNative::ParseNetworkId(n);
    if (net_id == 0) return 2;
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
