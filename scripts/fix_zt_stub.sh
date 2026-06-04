#!/bin/bash
# fix_zt_stub.sh — Fix ZeroTierNative.cpp stub
# Hapus JavaVM* g_jvm yang tidak perlu di stub
#
# Cara pakai:
#   bash scripts/fix_zt_stub.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
JNI_DIR="$PROJECT_ROOT/src/android/app/src/main/jni"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix ZeroTierNative.cpp stub"
echo "═══════════════════════════════════════════════════════"
echo ""

cat > "$JNI_DIR/ZeroTierNative.cpp" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// ZeroTierNative.cpp — STUB
// ZeroTier sekarang dikelola langsung dari Kotlin (ZeroTierManager.kt)
// File ini hanya stub agar CMakeLists tidak error saat compile.

#include "ZeroTierNative.h"

namespace ZeroTierNative {

ZTResult Init(const std::string&, uint64_t) { return ZTResult::OK; }
void        Shutdown()       {}
bool        IsReady()        { return false; }
std::string GetAssignedIP()  { return ""; }
uint64_t    GetNodeID()      { return 0; }
uint64_t    ParseNetworkId(const std::string& s) {
    try { return std::stoull(s, nullptr, 16); } catch (...) { return 0; }
}

} // namespace ZeroTierNative
EOF
echo "[OK] ZeroTierNative.cpp stub diperbaiki"

cat > "$JNI_DIR/jni_zt_bridge.cpp" << 'EOF'
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
EOF
echo "[OK] jni_zt_bridge.cpp stub diperbaiki"

cat > "$JNI_DIR/ZeroTierNative.h" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
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

ZTResult    Init(const std::string& storage_path, uint64_t network_id);
void        Shutdown();
bool        IsReady();
std::string GetAssignedIP();
uint64_t    GetNodeID();
uint64_t    ParseNetworkId(const std::string& hex_str);

} // namespace ZeroTierNative
EOF
echo "[OK] ZeroTierNative.h diperbaiki"

echo ""
echo "  git add ."
echo "  git commit -m \"fix: ZeroTierNative stub bersih tanpa JavaVM\""
echo "  git push origin DevElderLost-patch-4"
echo ""
