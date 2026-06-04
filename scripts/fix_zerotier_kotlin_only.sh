#!/bin/bash
# fix_zerotier_kotlin_only.sh
# Ganti pendekatan: ZeroTierNode dipanggil langsung dari Kotlin
# (reflection), tidak melalui C++ JNI sama sekali.
# Ini jauh lebih sederhana dan tidak ada masalah JVM attach.
#
# Cara pakai:
#   bash scripts/fix_zerotier_kotlin_only.sh

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
UTILS_DIR="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/utils"

[ -d "$UTILS_DIR" ] || error "Utils dir tidak ditemukan: $UTILS_DIR"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix: ZeroTier langsung dari Kotlin (tanpa C++ JNI)"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Tulis ulang ZeroTierManager.kt ────────────────────────────────
info "Tulis ulang ZeroTierManager.kt (Kotlin-only approach)..."

cat > "$UTILS_DIR/ZeroTierManager.kt" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// ZeroTierManager.kt — ZeroTierNode dipanggil langsung dari Kotlin
// menggunakan reflection ke com.zerotier.sockets.ZeroTierNode dari AAR.
// Tidak melalui C++ JNI — lebih sederhana dan tidak ada masalah JVM attach.

package org.citra.citra_emu.utils

import android.content.Context
import android.util.Log
import java.io.File

object ZeroTierManager {
    private const val TAG       = "ZeroTierManager"
    private const val PREFS_KEY = "zerotier_prefs"
    private const val KEY_NET   = "zt_network_id"

    // Nama class dari libzt-release.aar (hasil inspeksi)
    private const val ZT_NODE_CLASS = "com.zerotier.sockets.ZeroTierNode"

    enum class State { IDLE, STARTING, READY, ERROR }

    @Volatile var state: State = State.IDLE
        private set

    private var nodeInstance: Any? = null
    private var assignedIp: String = ""

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
        if (state == State.READY) { onReady(assignedIp); return }
        if (state == State.STARTING) { onError("Sedang dalam proses inisialisasi"); return }
        state = State.STARTING

        val storagePath = try {
            File(context.filesDir, "zt/$networkId").apply { mkdirs() }.absolutePath
        } catch (e: Exception) {
            state = State.ERROR
            onError("Gagal buat folder: ${e.message}")
            return
        }

        Thread {
            try {
                Log.i(TAG, "Init ZeroTierNode networkId=$networkId path=$storagePath")

                // Load class dari AAR via reflection
                val nodeClass = try {
                    Class.forName(ZT_NODE_CLASS)
                } catch (e: ClassNotFoundException) {
                    throw Exception(
                        "Class $ZT_NODE_CLASS tidak ditemukan. " +
                        "Pastikan libzt-release.aar ada di app/libs/ " +
                        "dan sudah ditambahkan di build.gradle"
                    )
                }

                // Buat instance: new ZeroTierNode()
                val node = nodeClass.getDeclaredConstructor().newInstance()
                nodeInstance = node

                // Log semua method yang tersedia (untuk debug)
                Log.d(TAG, "Method tersedia di ZeroTierNode:")
                nodeClass.methods.forEach { m ->
                    Log.d(TAG, "  ${m.name}(${m.parameterTypes.joinToString { it.simpleName }})")
                }

                // Cari dan panggil init method
                val initMethod = nodeClass.methods.firstOrNull { m ->
                    m.name == "init" && m.parameterTypes.isNotEmpty()
                } ?: throw Exception("Method init() tidak ditemukan")

                Log.i(TAG, "Memanggil init: ${initMethod.name}(${initMethod.parameterTypes.joinToString { it.simpleName }})")

                when (initMethod.parameterTypes.size) {
                    1 -> initMethod.invoke(node, storagePath)
                    2 -> initMethod.invoke(node, storagePath, 9994)
                    else -> initMethod.invoke(node, storagePath)
                }

                // Panggil start() jika ada
                nodeClass.methods.firstOrNull { it.name == "start" && it.parameterTypes.isEmpty() }
                    ?.invoke(node)

                // Tunggu online (15 detik)
                val onlineMethod = nodeClass.methods.firstOrNull {
                    (it.name == "isOnline" || it.name == "online") && it.parameterTypes.isEmpty()
                }
                val startTime = System.currentTimeMillis()
                while (System.currentTimeMillis() - startTime < 15000) {
                    val online = onlineMethod?.invoke(node) as? Boolean ?: true
                    if (online) break
                    Thread.sleep(200)
                }

                // Join network
                val netIdLong = networkId.toLong(16)
                val joinMethod = nodeClass.methods.firstOrNull { m ->
                    (m.name == "join" || m.name == "joinNetwork") &&
                    m.parameterTypes.size == 1 &&
                    (m.parameterTypes[0] == Long::class.java ||
                     m.parameterTypes[0] == java.lang.Long.TYPE)
                } ?: throw Exception("Method join(long) tidak ditemukan")

                Log.i(TAG, "Join network: $networkId (${netIdLong})")
                joinMethod.invoke(node, netIdLong)

                // Tunggu IP (20 detik)
                val ipMethod = nodeClass.methods.firstOrNull { m ->
                    (m.name == "getIPV4Address" || m.name == "getIPv4Address" ||
                     m.name == "getIpv4Address") &&
                    m.parameterTypes.size == 1
                }

                var ip = ""
                val ipStart = System.currentTimeMillis()
                while (System.currentTimeMillis() - ipStart < 20000) {
                    val result = ipMethod?.invoke(node, netIdLong) as? String
                    if (!result.isNullOrEmpty() && result.length > 6) {
                        ip = result
                        break
                    }
                    Thread.sleep(200)
                }

                if (ip.isEmpty()) {
                    throw Exception("Timeout IP — pastikan node diauthorize di my.zerotier.com")
                }

                assignedIp = ip
                state = State.READY
                Log.i(TAG, "ZeroTier ready IP=$ip")
                onReady(ip)

            } catch (e: Exception) {
                state = State.ERROR
                val msg = e.cause?.message ?: e.message ?: "Error tidak diketahui"
                Log.e(TAG, "ZeroTier error: $msg", e)
                onError(msg)
            }
        }.start()
    }

    fun shutdown() {
        if (state == State.IDLE) return
        try {
            nodeInstance?.let { node ->
                val nodeClass = node.javaClass
                // leave network
                nodeClass.methods.firstOrNull {
                    (it.name == "leave" || it.name == "leaveNetwork") &&
                    it.parameterTypes.size == 1
                }?.invoke(node, assignedIp.let {
                    getNetworkId(null as Context? ?: return@let 0L)
                })
                // stop
                nodeClass.methods.firstOrNull {
                    it.name == "stop" && it.parameterTypes.isEmpty()
                }?.invoke(node)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Shutdown error: ${e.message}")
        }
        nodeInstance = null
        assignedIp   = ""
        state        = State.IDLE
    }

    fun isReady()       = state == State.READY
    fun getAssignedIP() = assignedIp
}
EOF
success "ZeroTierManager.kt ditulis ulang (Kotlin reflection)"

# ── Update ZeroTierNative.cpp: stub kosong — tidak dipakai lagi ───
info "Update ZeroTierNative.cpp menjadi stub..."

JNI_DIR="$PROJECT_ROOT/src/android/app/src/main/jni"

cat > "$JNI_DIR/ZeroTierNative.cpp" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// ZeroTierNative.cpp — STUB
// ZeroTier sekarang dikelola langsung dari Kotlin (ZeroTierManager.kt)
// menggunakan reflection ke com.zerotier.sockets.ZeroTierNode.
// File ini hanya menyediakan implementasi kosong agar CMakeLists
// tidak error saat compile.

#include "ZeroTierNative.h"
#include "common/logging/log.h"

JavaVM* ZeroTierNative::g_jvm = nullptr;

namespace ZeroTierNative {

ZTResult Init(const std::string&, uint64_t) {
    // Tidak dipakai — ZeroTier dikelola dari Kotlin
    LOG_WARNING(Network, "[ZT] ZeroTierNative::Init() dipanggil tapi tidak dipakai");
    return ZTResult::OK;
}
void        Shutdown()       { /* stub */ }
bool        IsReady()        { return false; }
std::string GetAssignedIP()  { return ""; }
uint64_t    GetNodeID()      { return 0; }
uint64_t    ParseNetworkId(const std::string& s) {
    try { return std::stoull(s, nullptr, 16); } catch (...) { return 0; }
}

} // namespace ZeroTierNative
EOF
success "ZeroTierNative.cpp dijadikan stub"

# ── Update jni_zt_bridge.cpp — ztInit sekarang return 0 langsung ─
cat > "$JNI_DIR/jni_zt_bridge.cpp" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// jni_zt_bridge.cpp — Bridge stub
// ZeroTier dikelola dari Kotlin, fungsi ini hanya placeholder
// agar deklarasi @JvmStatic external fun zt*() di NetPlayManager.kt
// tidak error saat link.

#include <jni.h>
#include "ZeroTierNative.h"

#ifdef __cplusplus
extern "C" {
#endif

JNIEXPORT jint JNICALL
Java_org_citra_citra_1emu_utils_NetPlayManager_ztInit(
        JNIEnv*, jclass, jstring, jstring) {
    // Tidak dipakai — ZeroTier dikelola dari Kotlin ZeroTierManager
    return 0;
}

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
success "jni_zt_bridge.cpp dijadikan stub"

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Fix selesai!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: ZeroTier via Kotlin reflection, bypass C++ JNI\""
echo "  git push origin DevElderLost-patch-4"
echo ""
