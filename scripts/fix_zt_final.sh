#!/bin/bash
# fix_zt_final.sh — Fix ZeroTierManager dengan API ZeroTierNode yang benar
#
# API yang benar (dari source):
#   node.initFromStorage(path)        → setup storage
#   node.initSetEventHandler(handler) → opsional
#   node.start()                      → mulai node
#   node.isOnline()                   → cek online
#   node.join(networkIdLong)          → join network
#   node.getIPv4Address(networkIdLong) → InetAddress
#   node.stop()                       → stop node
#   node.leave(networkIdLong)         → leave network
#
# Cara pakai:
#   bash scripts/fix_zt_final.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
UTILS_DIR="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/utils"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix Final ZeroTierManager — API ZeroTierNode benar"
echo "═══════════════════════════════════════════════════════"
echo ""

cat > "$UTILS_DIR/ZeroTierManager.kt" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// ZeroTierManager.kt — Menggunakan API ZeroTierNode yang benar
// dari libzt-release.aar (com.zerotier.sockets.ZeroTierNode)
//
// API yang dipakai:
//   node.initFromStorage(path)         → setup storage identitas node
//   node.start()                       → mulai ZeroTier node
//   node.isOnline()                    → cek apakah node online
//   node.join(networkIdLong)           → join ke network
//   node.isNetworkTransportReady(id)   → cek network siap
//   node.getIPv4Address(networkIdLong) → InetAddress (IP di virtual network)
//   node.stop()                        → stop node
//   node.leave(networkIdLong)          → leave network

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
        val netIdLong = try {
            networkId.toLong(16)
        } catch (e: Exception) {
            state = State.ERROR
            onError("Network ID tidak valid: $networkId")
            return
        }
        currentNetworkId = netIdLong

        Thread {
            try {
                Log.i(TAG, "Init ZeroTierNode storage=$storagePath network=$networkId")

                // Load class ZeroTierNode dari AAR
                val nodeClass = try {
                    Class.forName(ZT_CLASS)
                } catch (e: ClassNotFoundException) {
                    throw Exception(
                        "Class $ZT_CLASS tidak ditemukan. " +
                        "Pastikan libzt-release.aar ada di app/libs/ " +
                        "dan sudah ditambahkan di build.gradle"
                    )
                }

                // Buat instance ZeroTierNode
                val node = nodeClass.getDeclaredConstructor().newInstance()
                nodeInstance = node

                // ── 1. initFromStorage(path) ─────────────────────────
                // Setup direktori penyimpanan identitas node
                val initStorage = nodeClass.getMethod("initFromStorage", String::class.java)
                val initResult = initStorage.invoke(node, storagePath) as Int
                Log.i(TAG, "initFromStorage result=$initResult")
                // ZTS_ERR_OK = 0, tapi initFromStorage boleh return non-0 jika
                // storage baru dibuat — tidak perlu throw error di sini

                // ── 2. start() ───────────────────────────────────────
                val startMethod = nodeClass.getMethod("start")
                val startResult = startMethod.invoke(node) as Int
                Log.i(TAG, "start() result=$startResult")
                if (startResult != 0) {
                    throw Exception("start() gagal: code $startResult")
                }

                // ── 3. Tunggu isOnline() (max 15 detik) ──────────────
                val onlineMethod = nodeClass.getMethod("isOnline")
                val t0 = System.currentTimeMillis()
                var online = false
                while (System.currentTimeMillis() - t0 < 15000) {
                    online = onlineMethod.invoke(node) as Boolean
                    if (online) break
                    Thread.sleep(200)
                }
                if (!online) {
                    throw Exception("Timeout — node tidak online setelah 15 detik. Cek koneksi internet.")
                }
                Log.i(TAG, "Node online!")

                // ── 4. join(networkIdLong) ───────────────────────────
                val joinMethod = nodeClass.getMethod("join", Long::class.java)
                val joinResult = joinMethod.invoke(node, netIdLong) as Int
                Log.i(TAG, "join($networkId) result=$joinResult")
                if (joinResult != 0) {
                    throw Exception("join() gagal: code $joinResult. Periksa Network ID.")
                }

                // ── 5. Tunggu isNetworkTransportReady + getIPv4Address ─
                // (max 20 detik)
                val transportReady = nodeClass.getMethod("isNetworkTransportReady", Long::class.java)
                val getIPv4 = nodeClass.getMethod("getIPv4Address", Long::class.java)
                var ip = ""
                val t1 = System.currentTimeMillis()
                while (System.currentTimeMillis() - t1 < 20000) {
                    val ready = transportReady.invoke(node, netIdLong) as Boolean
                    if (ready) {
                        val inetAddr = getIPv4.invoke(node, netIdLong) as? InetAddress
                        val hostAddr = inetAddr?.hostAddress ?: ""
                        if (hostAddr.isNotEmpty() && hostAddr != "0.0.0.0") {
                            ip = hostAddr
                            break
                        }
                    }
                    Thread.sleep(200)
                }

                if (ip.isEmpty()) {
                    // Coba ambil IP meski transport belum ready
                    val inetAddr = getIPv4.invoke(node, netIdLong) as? InetAddress
                    ip = inetAddr?.hostAddress ?: ""
                }

                if (ip.isEmpty()) {
                    throw Exception(
                        "IP tidak diterima setelah 20 detik. " +
                        "Pastikan node sudah diauthorize di my.zerotier.com → " +
                        "Network → Members → centang Auth ✓"
                    )
                }

                assignedIp = ip
                state = State.READY
                Log.i(TAG, "ZeroTier READY! IP=$ip")
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
                val cls = node.javaClass
                if (currentNetworkId != 0L) {
                    cls.getMethod("leave", Long::class.java).invoke(node, currentNetworkId)
                }
                cls.getMethod("stop").invoke(node)
                Log.i(TAG, "ZeroTier stopped")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Shutdown error: ${e.message}")
        }
        nodeInstance      = null
        assignedIp        = ""
        currentNetworkId  = 0L
        state             = State.IDLE
    }

    fun isReady()       = state == State.READY
    fun getAssignedIP() = assignedIp
}
EOF
echo "[OK] ZeroTierManager.kt ditulis ulang dengan API yang benar"

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "\033[0;32m  Fix selesai!\033[0m"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: ZeroTierManager pakai API ZeroTierNode yang benar\""
echo "  git push origin DevElderLost-patch-4"
echo ""
