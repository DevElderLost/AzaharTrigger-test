#!/bin/bash
# fix_zt_native_direct.sh — Panggil ZeroTierNative static methods langsung
# Bypass ZeroTierNode karena ProGuard obfuskasi method-nya
# ZeroTierNative memiliki semua method sebagai static native
#
# Cara pakai:
#   bash scripts/fix_zt_native_direct.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
UTILS_DIR="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/utils"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix: Panggil ZeroTierNative static methods langsung"
echo "═══════════════════════════════════════════════════════"
echo ""

cat > "$UTILS_DIR/ZeroTierManager.kt" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// ZeroTierManager.kt — Panggil ZeroTierNative static methods via reflection
//
// ZeroTierNode methods hilang karena ProGuard obfuskasi.
// ZeroTierNative menggunakan native methods yang tidak bisa diobfuskasi.
//
// Flow via ZeroTierNative:
//   ZeroTierNative.zts_init_from_storage(path) → setup storage
//   ZeroTierNative.zts_node_start()            → mulai node
//   ZeroTierNative.zts_node_is_online()        → 1 jika online
//   ZeroTierNative.zts_net_join(networkId)     → join network
//   ZeroTierNative.zts_net_transport_is_ready(id) → 1 jika siap
//   ZeroTierNative.zts_addr_get_str(id, AF_INET)  → IP string
//   ZeroTierNative.zts_node_stop()             → stop

package org.citra.citra_emu.utils

import android.content.Context
import android.util.Log
import java.io.File

object ZeroTierManager {
    private const val TAG        = "ZeroTierManager"
    private const val PREFS_KEY  = "zerotier_prefs"
    private const val KEY_NET    = "zt_network_id"
    private const val ZT_NATIVE  = "com.zerotier.sockets.ZeroTierNative"

    // ZTS_AF_INET = 2 (dari ZeroTierNative.java)
    private const val ZTS_AF_INET = 2
    private const val ZTS_ERR_OK  = 0

    enum class State { IDLE, STARTING, READY, ERROR }

    @Volatile var state: State = State.IDLE
        private set

    private var assignedIp: String = ""
    private var currentNetworkId: Long = 0L
    private var ztNativeClass: Class<*>? = null

    fun saveNetworkId(context: Context, id: String) =
        context.getSharedPreferences(PREFS_KEY, Context.MODE_PRIVATE)
            .edit().putString(KEY_NET, id).apply()

    fun getNetworkId(context: Context): String =
        context.getSharedPreferences(PREFS_KEY, Context.MODE_PRIVATE)
            .getString(KEY_NET, "") ?: ""

    fun hasNetworkId(context: Context) = getNetworkId(context).length == 16

    // Panggil static method di ZeroTierNative via reflection
    private fun callStatic(methodName: String, vararg args: Any?): Any? {
        val cls = ztNativeClass ?: throw Exception("ZeroTierNative belum diinisialisasi")
        val argTypes = args.map { a ->
            when (a) {
                is Long    -> Long::class.java
                is Int     -> Int::class.java
                is String  -> String::class.java
                is Boolean -> Boolean::class.java
                else       -> a?.javaClass
            }
        }
        // Cari method dengan nama dan parameter count
        val method = cls.methods.firstOrNull { m ->
            m.name == methodName && m.parameterTypes.size == args.size
        } ?: throw Exception("$methodName(${args.size} params) tidak ditemukan di ZeroTierNative")

        return method.invoke(null, *args)
    }

    fun init(
        context: Context,
        networkId: String,
        onReady: (ip: String) -> Unit,
        onError: (msg: String) -> Unit
    ) {
        if (state == State.READY) { onReady(assignedIp); return }
        if (state == State.STARTING) { onError("Sedang inisialisasi..."); return }
        state = State.STARTING

        val storagePath = File(context.filesDir, "zt/$networkId")
            .apply { mkdirs() }.absolutePath
        val netIdLong = try { networkId.toLong(16) } catch (e: Exception) {
            state = State.ERROR; onError("Network ID tidak valid: $networkId"); return
        }
        currentNetworkId = netIdLong

        Thread {
            try {
                Log.i(TAG, "Init via ZeroTierNative storage=$storagePath network=$networkId")

                // Load ZeroTierNative — static block otomatis:
                // System.loadLibrary("zt") + zts_init()
                val cls = try {
                    Class.forName(ZT_NATIVE)
                } catch (e: ClassNotFoundException) {
                    throw Exception("ZeroTierNative tidak ditemukan. Pastikan libzt-release.aar ada di app/libs/")
                }
                ztNativeClass = cls

                // Log method yang tersedia
                val methods = cls.methods.filter { it.name.startsWith("zts_") }
                    .sortedBy { it.name }
                    .joinToString(", ") { it.name }
                Log.d(TAG, "ZTS methods: $methods")

                // ── 1. zts_init_from_storage(path) ───────────────────
                val r1 = callStatic("zts_init_from_storage", storagePath) as? Int ?: -1
                Log.i(TAG, "zts_init_from_storage=$r1")

                // ── 2. zts_node_start() ───────────────────────────────
                val r2 = callStatic("zts_node_start") as? Int ?: -1
                Log.i(TAG, "zts_node_start=$r2")
                if (r2 != ZTS_ERR_OK) throw Exception("zts_node_start gagal: code=$r2")

                // ── 3. Tunggu zts_node_is_online() == 1 ──────────────
                Log.i(TAG, "Menunggu node online...")
                val t0 = System.currentTimeMillis()
                while (System.currentTimeMillis() - t0 < 15000) {
                    val online = callStatic("zts_node_is_online") as? Int ?: 0
                    if (online == 1) { Log.i(TAG, "Node online!"); break }
                    Thread.sleep(200)
                }
                val isOnline = callStatic("zts_node_is_online") as? Int ?: 0
                if (isOnline != 1) throw Exception(
                    "Timeout — node tidak online. Cek koneksi internet."
                )

                // ── 4. zts_net_join(networkId) ────────────────────────
                val r4 = callStatic("zts_net_join", netIdLong) as? Int ?: -1
                Log.i(TAG, "zts_net_join=$r4")
                if (r4 != ZTS_ERR_OK) throw Exception("zts_net_join gagal: code=$r4")

                // ── 5. Tunggu transport ready + ambil IP ──────────────
                Log.i(TAG, "Menunggu IP...")
                var ip = ""
                val t1 = System.currentTimeMillis()
                while (System.currentTimeMillis() - t1 < 25000) {
                    val ready = callStatic("zts_net_transport_is_ready", netIdLong) as? Int ?: 0
                    if (ready == 1) {
                        val addr = callStatic("zts_addr_get_str", netIdLong, ZTS_AF_INET) as? String ?: ""
                        Log.d(TAG, "IP candidate: '$addr'")
                        if (addr.isNotEmpty() && addr != "0.0.0.0" &&
                            addr != "null" && !addr.startsWith("0.") &&
                            addr.contains(".")) {
                            ip = addr; break
                        }
                    }
                    Thread.sleep(300)
                }

                if (ip.isEmpty()) throw Exception(
                    "IP tidak diterima. Authorize node:\n" +
                    "my.zerotier.com → Networks → Members → ✓ Auth"
                )

                assignedIp = ip
                state = State.READY
                Log.i(TAG, "ZeroTier READY! IP=$ip")
                onReady(ip)

            } catch (e: ExceptionInInitializerError) {
                state = State.ERROR
                val msg = "libzt.so tidak ditemukan. " +
                    "AAR arm64-v8a diperlukan: ${e.cause?.message ?: e.message}"
                Log.e(TAG, msg, e)
                onError(msg)
            } catch (e: ClassNotFoundException) {
                state = State.ERROR
                onError("libzt AAR tidak ditemukan di app/libs/")
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
            if (currentNetworkId != 0L)
                callStatic("zts_net_leave", currentNetworkId)
            callStatic("zts_node_stop")
        } catch (e: Exception) { Log.e(TAG, "Shutdown: ${e.message}") }
        assignedIp = ""; currentNetworkId = 0L
        state = State.IDLE
    }

    fun isReady()       = state == State.READY
    fun getAssignedIP() = assignedIp
}
EOF
echo "[OK] ZeroTierManager.kt ditulis ulang via ZeroTierNative static methods"

echo ""
echo "  git add ."
echo "  git commit -m \"fix: ZeroTierManager via ZeroTierNative static methods bypass ProGuard\""
echo "  git push origin DevElderLost-patch-4"
echo ""
