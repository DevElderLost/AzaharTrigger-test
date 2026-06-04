// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// jni_zt_bridge.cpp — Stub bridge, ZeroTier dikelola dari Kotlin

#include <jni.h>
#include "ZeroTierNative.h"

#ifdef __cplusplus
extern "C" {
#endif

JNIEXPORT jint JNICALL
Java_org_citra_citra_1emu_utils_NetPlayManager_ztInit(
        JNIEnv*, jclass, jstring, jstring) { return 0; }

JNIEXPORT void JNICALL
Java_org_citra_citra_1emu_utils_NetPlayManager_ztShutdown(JNIEnv*, jclass) {}

JNIEXPORT jstring JNICALL
Java_org_citra_citra_1emu_utils_NetPlayManager_ztGetAssignedIP(JNIEnv* env, jclass) {
    return env->NewStringUTF("");
}

JNIEXPORT jboolean JNICALL
Java_org_citra_citra_1emu_utils_NetPlayManager_ztIsReady(JNIEnv*, jclass) {
    return JNI_FALSE;
}

#ifdef __cplusplus
}
#endif
