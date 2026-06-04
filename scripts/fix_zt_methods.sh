#!/bin/bash
# fix_zt_methods.sh — Fix method names ZeroTierNode
# Error: Method init() tidak ditemukan
# Solusi: coba semua kemungkinan nama method + tampilkan di UI
#
# Cara pakai:
#   bash scripts/fix_zt_methods.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
UTILS_DIR="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/utils"

echo "[INFO] Tulis ulang ZeroTierManager.kt dengan method discovery..."

cat > "$UTILS_DIR/ZeroTierManager.kt" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
package org.citra.citra_emu.utils

import android.content.Context
import android.util.Log
import java.io.File
import java.lang.reflect.Method

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

    fun saveNetworkId(context: Context, id: String) =
        context.getSharedPreferences(PREFS_KEY, Context.MODE_PRIVATE)
            .edit().putString(KEY_NET, id).apply()

    fun getNetworkId(context: Context): String =
        context.getSharedPreferences(PREFS_KEY, Context.MODE_PRIVATE)
            .getString(KEY_NET, "") ?: ""

    fun hasNetworkId(context: Context) = getNetworkId(context).length == 16

    // Cari method berdasarkan nama dan jumlah parameter
    private fun findMethod(cls: Class<*>, vararg names: String, paramCount: Int = -1): Method? {
        return cls.methods.firstOrNull { m ->
            names.any { it.equals(m.name, ignoreCase = true) } &&
            (paramCount == -1 || m.parameterTypes.size == paramCount)
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

        Thread {
            try {
                val nodeClass = Class.forName(ZT_CLASS)

                // Log SEMUA method untuk debug
                val allMethods = nodeClass.methods.joinToString("\n") { m ->
                    "  ${m.name}(${m.parameterTypes.joinToString { it.simpleName }}): ${m.returnType.simpleName}"
                }
                Log.d(TAG, "Semua method di ZeroTierNode:\n$allMethods")

                // Buat instance
                val node = nodeClass.getDeclaredConstructor().newInstance()
                nodeInstance = node

                val netIdLong = networkId.toLong(16)
                val STEP = 200L

                // ── 1. Start/Init node ───────────────────────────────
                // Coba berbagai nama method yang mungkin
                val startMethod = findMethod(nodeClass,
                    "init", "start", "begin", "startNode", "initNode",
                    "startService", "launch", "run", "open"
                )

                if (startMethod == null) {
                    // Tampilkan method yang ada untuk diagnosa
                    val available = nodeClass.methods
                        .filter { !listOf("wait","notify","notifyAll","toString","hashCode","equals","getClass").contains(it.name) }
                        .joinToString(", ") { "${it.name}(${it.parameterTypes.size})" }
                    throw Exception("Method start/init tidak ditemukan.\nMethod tersedia: $available")
                }

                Log.i(TAG, "Memanggil: ${startMethod.name}(${startMethod.parameterTypes.joinToString { it.simpleName }})")

                // Panggil dengan parameter yang sesuai
                when {
                    startMethod.parameterTypes.isEmpty() ->
                        startMethod.invoke(node)
                    startMethod.parameterTypes.size == 1 &&
                    startMethod.parameterTypes[0] == String::class.java ->
                        startMethod.invoke(node, storagePath)
                    startMethod.parameterTypes.size == 2 &&
                    startMethod.parameterTypes[0] == String::class.java ->
                        startMethod.invoke(node, storagePath, 9994)
                    else ->
                        startMethod.invoke(node, storagePath)
                }

                // ── 2. Tunggu online ─────────────────────────────────
                val onlineMethod = findMethod(nodeClass,
                    "isOnline", "online", "isRunning", "running",
                    "isReady", "ready", "isStarted", "started"
                )
                val t0 = System.currentTimeMillis()
                while (System.currentTimeMillis() - t0 < 15000) {
                    val online = onlineMethod?.invoke(node) as? Boolean ?: true
                    if (online) break
                    Thread.sleep(STEP)
                }
                Log.i(TAG, "Node online/siap")

                // ── 3. Join network ──────────────────────────────────
                val joinMethod = findMethod(nodeClass,
                    "join", "joinNetwork", "connect", "connectTo",
                    "addNetwork", "attach",
                    paramCount = 1
                ) ?: throw Exception("Method join() tidak ditemukan")

                Log.i(TAG, "Join: ${joinMethod.name}($netIdLong)")
                when (joinMethod.parameterTypes[0]) {
                    Long::class.java, java.lang.Long.TYPE -> joinMethod.invoke(node, netIdLong)
                    String::class.java -> joinMethod.invoke(node, networkId)
                    else -> joinMethod.invoke(node, netIdLong)
                }

                // ── 4. Tunggu IP ─────────────────────────────────────
                val ipMethod = findMethod(nodeClass,
                    "getIPV4Address", "getIPv4Address", "getIpv4Address",
                    "getAddress", "getIP", "getIp", "ipv4Address",
                    "getAssignedAddress", "getNetworkAddress"
                )

                var ip = ""
                val t1 = System.currentTimeMillis()
                while (System.currentTimeMillis() - t1 < 20000) {
                    val result = try {
                        when (ipMethod?.parameterTypes?.size) {
                            0    -> ipMethod.invoke(node) as? String
                            1    -> ipMethod?.invoke(node, netIdLong) as? String
                            else -> null
                        }
                    } catch (e: Exception) { null }

                    if (!result.isNullOrEmpty() && result.length > 6 &&
                        result != "0.0.0.0" && result != "null") {
                        ip = result
                        break
                    }
                    Thread.sleep(STEP)
                }

                if (ip.isEmpty()) {
                    throw Exception("Timeout IP — authorize node di my.zerotier.com")
                }

                assignedIp = ip
                state = State.READY
                Log.i(TAG, "ZeroTier ready IP=$ip")
                onReady(ip)

            } catch (e: ClassNotFoundException) {
                state = State.ERROR
                onError("Class ZeroTierNode tidak ditemukan. Pastikan libzt-release.aar sudah ditambahkan di app/libs/")
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
                findMethod(cls, "leave", "leaveNetwork", paramCount = 1)
                    ?.invoke(node, assignedIp.toLongOrNull() ?: 0L)
                findMethod(cls, "stop", "close", "shutdown", paramCount = 0)
                    ?.invoke(node)
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
echo "[OK] ZeroTierManager.kt ditulis ulang dengan method discovery"

echo ""
echo "  git add ."
echo "  git commit -m \"fix: ZeroTierManager method discovery untuk ZeroTierNode API\""
echo "  git push origin DevElderLost-patch-4"
echo ""
