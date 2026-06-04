#!/bin/bash
# fix_zt_reflection.sh — Fix NoSuchMethodException di ZeroTierManager
#
# Cara pakai:
#   bash scripts/fix_zt_reflection.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
UTILS_DIR="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/utils"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix ZeroTierManager — reflection yang benar"
echo "═══════════════════════════════════════════════════════"
echo ""

cat > "$UTILS_DIR/ZeroTierManager.kt" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
package org.citra.citra_emu.utils

import android.content.Context
import android.util.Log
import java.io.File
import java.lang.reflect.Method
import java.net.InetAddress

object ZeroTierManager {
    private const val TAG       = "ZeroTierManager"
    private const val PREFS_KEY = "zerotier_prefs"
    private const val KEY_NET   = "zt_network_id"
    private const val ZT_CLASS  = "com.zerotier.sockets.ZeroTierNode"

    enum class State { IDLE, STARTING, READY, ERROR }

    @Volatile var state: State = State.IDLE
        private set

    private var nodeInstance: Any? = null
    private var assignedIp: String = ""
    private var currentNetworkId: Long = 0L

    fun saveNetworkId(context: Context, id: String) =
        context.getSharedPreferences(PREFS_KEY, Context.MODE_PRIVATE)
            .edit().putString(KEY_NET, id).apply()

    fun getNetworkId(context: Context): String =
        context.getSharedPreferences(PREFS_KEY, Context.MODE_PRIVATE)
            .getString(KEY_NET, "") ?: ""

    fun hasNetworkId(context: Context) = getNetworkId(context).length == 16

    // Helper: cari method berdasarkan nama saja (ignore parameter types)
    private fun Class<*>.findMethod(name: String): Method? =
        this.methods.firstOrNull { it.name == name }

    // Helper: cari method berdasarkan nama + jumlah parameter
    private fun Class<*>.findMethod(name: String, paramCount: Int): Method? =
        this.methods.firstOrNull { it.name == name && it.parameterTypes.size == paramCount }

    // Helper: invoke method dengan parameter yang sesuai tipenya
    private fun invokeMethod(node: Any, method: Method, vararg args: Any?): Any? {
        return try {
            method.isAccessible = true
            method.invoke(node, *args)
        } catch (e: Exception) {
            Log.e(TAG, "invokeMethod ${method.name} error: ${e.cause?.message ?: e.message}")
            throw e
        }
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

        val netIdLong = try {
            networkId.toLong(16)
        } catch (e: Exception) {
            state = State.ERROR
            onError("Network ID tidak valid")
            return
        }
        currentNetworkId = netIdLong

        Thread {
            try {
                // Load class
                val nodeClass = Class.forName(ZT_CLASS)
                val node = nodeClass.getDeclaredConstructor().newInstance()
                nodeInstance = node

                // Log semua method untuk debug
                Log.d(TAG, "Method ZeroTierNode:")
                nodeClass.methods.forEach {
                    Log.d(TAG, "  ${it.name}(${it.parameterTypes.joinToString { p -> p.simpleName }}): ${it.returnType.simpleName}")
                }

                // ── 1. initFromStorage(String) ────────────────────────
                val initStorage = nodeClass.findMethod("initFromStorage", 1)
                    ?: throw Exception("initFromStorage() tidak ditemukan")

                Log.i(TAG, "initFromStorage($storagePath)")
                // Parameter tipenya String, invoke dengan cast
                val initResult = initStorage.invoke(node, storagePath)
                Log.i(TAG, "initFromStorage result=$initResult")

                // ── 2. start() ────────────────────────────────────────
                val startMethod = nodeClass.findMethod("start", 0)
                    ?: throw Exception("start() tidak ditemukan")

                val startResult = startMethod.invoke(node)
                Log.i(TAG, "start() result=$startResult")

                // ── 3. Tunggu isOnline() ──────────────────────────────
                val onlineMethod = nodeClass.findMethod("isOnline", 0)
                val t0 = System.currentTimeMillis()
                while (System.currentTimeMillis() - t0 < 15000) {
                    val online = onlineMethod?.invoke(node) as? Boolean ?: true
                    if (online) { Log.i(TAG, "Node online!"); break }
                    Thread.sleep(200)
                }

                // ── 4. join(long) ─────────────────────────────────────
                val joinMethod = nodeClass.findMethod("join", 1)
                    ?: throw Exception("join() tidak ditemukan")

                // Konversi ke tipe parameter yang benar
                val joinArg: Any = when (joinMethod.parameterTypes[0]) {
                    Long::class.java, java.lang.Long.TYPE -> netIdLong
                    String::class.java -> networkId
                    else -> netIdLong
                }
                val joinResult = joinMethod.invoke(node, joinArg)
                Log.i(TAG, "join($networkId) result=$joinResult")

                // ── 5. Tunggu IP ──────────────────────────────────────
                val transportMethod = nodeClass.findMethod("isNetworkTransportReady", 1)
                val getIpMethod = nodeClass.findMethod("getIPv4Address", 1)
                    ?: nodeClass.findMethod("getIPV4Address", 1)

                var ip = ""
                val t1 = System.currentTimeMillis()
                while (System.currentTimeMillis() - t1 < 25000) {
                    // Cek transport ready
                    val ready = try {
                        transportMethod?.invoke(node, netIdLong) as? Boolean ?: true
                    } catch (e: Exception) { true }

                    if (ready && getIpMethod != null) {
                        val inetArg: Any = when (getIpMethod.parameterTypes[0]) {
                            Long::class.java, java.lang.Long.TYPE -> netIdLong
                            String::class.java -> networkId
                            else -> netIdLong
                        }
                        val result = try {
                            getIpMethod.invoke(node, inetArg)
                        } catch (e: Exception) { null }

                        val hostAddr = when (result) {
                            is InetAddress -> result.hostAddress ?: ""
                            is String      -> result
                            else           -> ""
                        }
                        if (hostAddr.isNotEmpty() && hostAddr != "0.0.0.0" &&
                            !hostAddr.startsWith("0.") && hostAddr != "null") {
                            ip = hostAddr
                            break
                        }
                    }
                    Thread.sleep(300)
                }

                if (ip.isEmpty()) {
                    throw Exception(
                        "IP tidak diterima. Pastikan node sudah diauthorize:\n" +
                        "my.zerotier.com → Networks → ${networkId.take(8)}... → Members → ✓ Auth"
                    )
                }

                assignedIp = ip
                state = State.READY
                Log.i(TAG, "ZeroTier READY! IP=$ip")
                onReady(ip)

            } catch (e: ClassNotFoundException) {
                state = State.ERROR
                onError("libzt AAR tidak ditemukan. Pastikan libzt-release.aar ada di app/libs/")
            } catch (e: Exception) {
                state = State.ERROR
                val msg = e.cause?.message ?: e.message ?: "Error tidak diketahui"
                Log.e(TAG, "ZeroTier error", e)
                onError(msg)
            }
        }.start()
    }

    fun shutdown() {
        if (state == State.IDLE) return
        try {
            nodeInstance?.let { node ->
                val cls = node.javaClass
                if (currentNetworkId != 0L) {
                    cls.findMethod("leave", 1)?.invoke(node, currentNetworkId)
                }
                cls.findMethod("stop", 0)?.invoke(node)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Shutdown error: ${e.message}")
        }
        nodeInstance     = null
        assignedIp       = ""
        currentNetworkId = 0L
        state            = State.IDLE
    }

    fun isReady()       = state == State.READY
    fun getAssignedIP() = assignedIp
}
EOF
echo "[OK] ZeroTierManager.kt ditulis ulang"

echo ""
echo "  git add ."
echo "  git commit -m \"fix: ZeroTierManager reflection method invoke yang benar\""
echo "  git push origin DevElderLost-patch-4"
echo ""
