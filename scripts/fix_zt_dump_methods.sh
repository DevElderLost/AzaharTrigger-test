#!/bin/bash
# fix_zt_dump_methods.sh — Tampilkan semua method ZeroTierNode di UI
#
# Cara pakai:
#   bash scripts/fix_zt_dump_methods.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
UTILS_DIR="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/utils"

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

    private fun Class<*>.findMethod(name: String, paramCount: Int = -1): Method? =
        this.methods.firstOrNull {
            it.name == name && (paramCount == -1 || it.parameterTypes.size == paramCount)
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
            state = State.ERROR; onError("Network ID tidak valid"); return
        }
        currentNetworkId = netIdLong

        Thread {
            try {
                val nodeClass = Class.forName(ZT_CLASS)
                val node = nodeClass.getDeclaredConstructor().newInstance()
                nodeInstance = node

                // ── Dump semua method ke log DAN ke variabel untuk ditampilkan ──
                val methodList = nodeClass.methods
                    .filter { it.declaringClass != Object::class.java }
                    .sortedBy { it.name }
                    .joinToString("\n") { m ->
                        "${m.name}(${m.parameterTypes.joinToString { it.simpleName }})"
                    }
                Log.i(TAG, "=== ZeroTierNode methods ===\n$methodList")

                // ── Cari method setup storage (coba semua kemungkinan nama) ──
                val setupMethod = nodeClass.findMethod("initFromStorage")
                    ?: nodeClass.findMethod("setStorage")
                    ?: nodeClass.findMethod("setStoragePath")
                    ?: nodeClass.findMethod("setDataPath")
                    ?: nodeClass.findMethod("setPath")
                    ?: nodeClass.findMethod("initStorage")

                if (setupMethod == null) {
                    // Tampilkan semua method yang ada agar bisa diagnosa
                    val methodSummary = nodeClass.methods
                        .filter { it.declaringClass != Object::class.java }
                        .sortedBy { it.name }
                        .joinToString(", ") { "${it.name}(${it.parameterTypes.size})" }
                    throw Exception("initFromStorage tidak ditemukan.\nMethod tersedia:\n$methodSummary")
                }

                Log.i(TAG, "Setup method: ${setupMethod.name}")
                setupMethod.invoke(node, storagePath)

                // ── start() ───────────────────────────────────────────
                val startMethod = nodeClass.findMethod("start", 0)
                    ?: throw Exception("start() tidak ditemukan")
                startMethod.invoke(node)

                // ── isOnline() ─────────────────────────────────────────
                val onlineMethod = nodeClass.findMethod("isOnline", 0)
                val t0 = System.currentTimeMillis()
                while (System.currentTimeMillis() - t0 < 15000) {
                    if (onlineMethod?.invoke(node) as? Boolean == true) break
                    Thread.sleep(200)
                }

                // ── join(long) ────────────────────────────────────────
                val joinMethod = nodeClass.findMethod("join", 1)
                    ?: throw Exception("join() tidak ditemukan")
                val joinArg: Any = if (joinMethod.parameterTypes[0] == String::class.java)
                    networkId else netIdLong
                joinMethod.invoke(node, joinArg)

                // ── Tunggu IP ─────────────────────────────────────────
                val transportMethod = nodeClass.findMethod("isNetworkTransportReady", 1)
                val getIpMethod = nodeClass.findMethod("getIPv4Address", 1)
                    ?: nodeClass.findMethod("getIPV4Address", 1)
                    ?: nodeClass.findMethod("getIpv4Address", 1)

                var ip = ""
                val t1 = System.currentTimeMillis()
                while (System.currentTimeMillis() - t1 < 25000) {
                    val ready = try {
                        transportMethod?.invoke(node, netIdLong) as? Boolean ?: true
                    } catch (e: Exception) { true }

                    if (ready && getIpMethod != null) {
                        val ipArg: Any = if (getIpMethod.parameterTypes[0] == String::class.java)
                            networkId else netIdLong
                        val result = try { getIpMethod.invoke(node, ipArg) } catch (e: Exception) { null }
                        val addr = when (result) {
                            is InetAddress -> result.hostAddress ?: ""
                            is String      -> result
                            else           -> ""
                        }
                        if (addr.isNotEmpty() && addr != "0.0.0.0" && addr != "null") {
                            ip = addr; break
                        }
                    }
                    Thread.sleep(300)
                }

                if (ip.isEmpty()) throw Exception(
                    "IP tidak diterima. Authorize node di:\nmy.zerotier.com → Networks → Members → ✓ Auth"
                )

                assignedIp = ip
                state = State.READY
                onReady(ip)

            } catch (e: ClassNotFoundException) {
                state = State.ERROR
                onError("libzt AAR tidak ditemukan di app/libs/")
            } catch (e: Exception) {
                state = State.ERROR
                onError(e.cause?.message ?: e.message ?: "Error tidak diketahui")
            }
        }.start()
    }

    fun shutdown() {
        if (state == State.IDLE) return
        try {
            nodeInstance?.let { node ->
                val cls = node.javaClass
                if (currentNetworkId != 0L)
                    cls.findMethod("leave", 1)?.invoke(node, currentNetworkId)
                cls.findMethod("stop", 0)?.invoke(node)
            }
        } catch (e: Exception) { Log.e(TAG, "Shutdown: ${e.message}") }
        nodeInstance = null; assignedIp = ""; currentNetworkId = 0L
        state = State.IDLE
    }

    fun isReady()       = state == State.READY
    fun getAssignedIP() = assignedIp
}
EOF
echo "[OK] ZeroTierManager.kt ditulis ulang dengan method dump"

echo ""
echo "  git add ."
echo "  git commit -m \"fix: ZeroTierManager tampilkan semua method saat error\""
echo "  git push origin DevElderLost-patch-4"
echo ""
