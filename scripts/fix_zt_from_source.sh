#!/bin/bash
# fix_zt_from_source.sh — Tulis ZeroTierManager berdasarkan source yang tepat
#
# Cara pakai:
#   bash scripts/fix_zt_from_source.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
UTILS_DIR="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/utils"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix ZeroTierManager — berdasarkan source ZeroTierNode"
echo "═══════════════════════════════════════════════════════"
echo ""

# Berdasarkan ZeroTierNode.java yang kita lihat, method yang ada:
# - initFromStorage(String) → ZeroTierNative.zts_init_from_storage(str)
# - start()                 → ZeroTierNative.zts_node_start()
# - stop()                  → ZeroTierNative.zts_node_stop()
# - isOnline()              → ZeroTierNative.zts_node_is_online() == 1
# - join(long)              → ZeroTierNative.zts_net_join(j)
# - leave(long)             → ZeroTierNative.zts_net_leave(j)
# - getIPv4Address(long)    → InetAddress dari zts_addr_get_str(j, ZTS_AF_INET)
# - isNetworkTransportReady(long) → zts_net_transport_is_ready(j) == 1
# - getId()                 → zts_node_get_id()
#
# ZeroTierNative static block: System.loadLibrary("zt") + zts_init()
# Method tersedia kosong karena declaringClass filter → hapus filter itu

cat > "$UTILS_DIR/ZeroTierManager.kt" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// ZeroTierManager.kt — Berdasarkan source ZeroTierNode.java dari AAR
//
// Flow:
//   1. new ZeroTierNode()          → instance (ZeroTierNative di-load via static block)
//   2. node.initFromStorage(path)  → setup storage identitas
//   3. node.start()                → mulai ZeroTier node
//   4. tunggu node.isOnline()      → node terhubung ke ZeroTier network
//   5. node.join(networkIdLong)    → join virtual network
//   6. tunggu isNetworkTransportReady → network siap
//   7. node.getIPv4Address(id)     → InetAddress → hostAddress

package org.citra.citra_emu.utils

import android.content.Context
import android.util.Log
import java.io.File
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
                Log.i(TAG, "Init ZeroTierNode storage=$storagePath networkId=$networkId")

                // ── Load class — static block ZeroTierNative akan memanggil ──
                // System.loadLibrary("zt") dan zts_init() secara otomatis
                val nodeClass = try {
                    Class.forName(ZT_CLASS)
                } catch (e: ClassNotFoundException) {
                    throw Exception("Class ZeroTierNode tidak ditemukan. Pastikan libzt-release.aar ada di app/libs/")
                }

                // ── Buat instance ─────────────────────────────────────
                val node = try {
                    nodeClass.getDeclaredConstructor().newInstance()
                } catch (e: Exception) {
                    // Jika static initializer gagal (libzt.so tidak ditemukan)
                    throw Exception("Gagal buat ZeroTierNode: ${e.cause?.message ?: e.message}")
                }
                nodeInstance = node

                // ── Log method yang benar-benar ada (tanpa filter) ────
                val allMethods = nodeClass.methods.joinToString(", ") {
                    "${it.name}(${it.parameterTypes.size})"
                }
                Log.d(TAG, "Methods: $allMethods")

                // ── 1. initFromStorage(String) ────────────────────────
                val mInitStorage = nodeClass.methods
                    .firstOrNull { it.name == "initFromStorage" }
                    ?: throw Exception(
                        "initFromStorage tidak ada. Methods: $allMethods"
                    )
                val r1 = mInitStorage.invoke(node, storagePath) as? Int ?: 0
                Log.i(TAG, "initFromStorage=$r1")

                // ── 2. start() ────────────────────────────────────────
                val mStart = nodeClass.methods.firstOrNull { it.name == "start" && it.parameterTypes.isEmpty() }
                    ?: throw Exception("start() tidak ditemukan")
                val r2 = mStart.invoke(node) as? Int ?: 0
                Log.i(TAG, "start()=$r2")
                if (r2 != 0) throw Exception("start() gagal: code=$r2")

                // ── 3. Tunggu isOnline() ──────────────────────────────
                val mOnline = nodeClass.methods.firstOrNull {
                    it.name == "isOnline" && it.parameterTypes.isEmpty()
                }
                Log.i(TAG, "Menunggu node online...")
                val t0 = System.currentTimeMillis()
                while (System.currentTimeMillis() - t0 < 15000) {
                    val online = mOnline?.invoke(node) as? Boolean ?: true
                    if (online) { Log.i(TAG, "Node online!"); break }
                    Thread.sleep(200)
                }

                // ── 4. join(long) ─────────────────────────────────────
                val mJoin = nodeClass.methods.firstOrNull {
                    it.name == "join" && it.parameterTypes.size == 1
                } ?: throw Exception("join() tidak ditemukan")

                val joinArg: Any = when {
                    mJoin.parameterTypes[0].name.contains("long", ignoreCase = true) ||
                    mJoin.parameterTypes[0].name.contains("Long", ignoreCase = false) -> netIdLong
                    mJoin.parameterTypes[0] == String::class.java -> networkId
                    else -> netIdLong
                }
                val r4 = mJoin.invoke(node, joinArg) as? Int ?: 0
                Log.i(TAG, "join($networkId)=$r4")

                // ── 5. Tunggu isNetworkTransportReady + getIPv4Address ─
                val mReady = nodeClass.methods.firstOrNull {
                    it.name == "isNetworkTransportReady" && it.parameterTypes.size == 1
                }
                val mGetIp = nodeClass.methods.firstOrNull {
                    it.name.equals("getIPv4Address", ignoreCase = true) &&
                    it.parameterTypes.size == 1
                }

                Log.i(TAG, "Menunggu IP...")
                var ip = ""
                val t1 = System.currentTimeMillis()
                while (System.currentTimeMillis() - t1 < 25000) {
                    val ready = try {
                        mReady?.invoke(node, netIdLong) as? Boolean ?: true
                    } catch (e: Exception) { true }

                    if (ready && mGetIp != null) {
                        val ipArg: Any = when {
                            mGetIp.parameterTypes[0].name.contains("long", ignoreCase = true) ||
                            mGetIp.parameterTypes[0].name.contains("Long") -> netIdLong
                            mGetIp.parameterTypes[0] == String::class.java -> networkId
                            else -> netIdLong
                        }
                        val result = try { mGetIp.invoke(node, ipArg) } catch (e: Exception) { null }
                        val addr = when (result) {
                            is InetAddress -> result.hostAddress ?: ""
                            is String      -> result
                            null           -> ""
                            else           -> result.toString()
                        }
                        Log.d(TAG, "IP result: '$addr'")
                        if (addr.isNotEmpty() && addr != "0.0.0.0" &&
                            addr != "null" && !addr.startsWith("0.")) {
                            ip = addr; break
                        }
                    }
                    Thread.sleep(300)
                }

                if (ip.isEmpty()) throw Exception(
                    "IP tidak diterima. Authorize node di my.zerotier.com → Networks → Members → ✓ Auth"
                )

                assignedIp = ip
                state = State.READY
                Log.i(TAG, "ZeroTier READY! IP=$ip")
                onReady(ip)

            } catch (e: ExceptionInInitializerError) {
                // ZeroTierNative.static { System.loadLibrary("zt") } gagal
                state = State.ERROR
                val msg = "libzt.so tidak ditemukan di APK. " +
                    "Pastikan AAR arm64-v8a tersedia: ${e.cause?.message ?: e.message}"
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
            nodeInstance?.let { node ->
                val cls = node.javaClass
                if (currentNetworkId != 0L)
                    cls.methods.firstOrNull { it.name == "leave" && it.parameterTypes.size == 1 }
                        ?.invoke(node, currentNetworkId)
                cls.methods.firstOrNull { it.name == "stop" && it.parameterTypes.isEmpty() }
                    ?.invoke(node)
            }
        } catch (e: Exception) { Log.e(TAG, "Shutdown: ${e.message}") }
        nodeInstance = null; assignedIp = ""; currentNetworkId = 0L
        state = State.IDLE
    }

    fun isReady()       = state == State.READY
    fun getAssignedIP() = assignedIp
}
EOF
echo "[OK] ZeroTierManager.kt ditulis berdasarkan source yang benar"

echo ""
echo "  git add ."
echo "  git commit -m \"fix: ZeroTierManager berdasarkan source ZeroTierNode yang tepat\""
echo "  git push origin DevElderLost-patch-4"
echo ""
