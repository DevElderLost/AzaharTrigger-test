// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
package org.citra.citra_emu.utils

import android.content.Context
import android.util.Log
import java.io.File

object ZeroTierManager {
    private const val TAG        = "ZeroTierManager"
    private const val PREFS_KEY  = "zerotier_prefs"
    private const val KEY_NET    = "zt_network_id"
    private const val ZT_NATIVE  = "com.zerotier.sockets.ZeroTierNative"
    private const val ZTS_AF_INET = 2
    private const val ZTS_ERR_OK  = 0

    enum class State { IDLE, STARTING, READY, STOPPING, ERROR }

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

    private fun callStatic(methodName: String, vararg args: Any?): Any? {
        val cls = ztNativeClass ?: return null
        val method = cls.methods.firstOrNull { m ->
            m.name == methodName && m.parameterTypes.size == args.size
        } ?: throw Exception("$methodName(${args.size} params) tidak ditemukan")
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
        if (state == State.STOPPING) { onError("Sedang memutus koneksi..."); return }
        state = State.STARTING

        val storagePath = File(context.filesDir, "zt/$networkId")
            .apply { mkdirs() }.absolutePath
        val netIdLong = try { networkId.toLong(16) } catch (e: Exception) {
            state = State.ERROR; onError("Network ID tidak valid: $networkId"); return
        }
        currentNetworkId = netIdLong

        Thread {
            try {
                Log.i(TAG, "Init ZeroTierNative storage=$storagePath network=$networkId")
                val cls = Class.forName(ZT_NATIVE)
                ztNativeClass = cls

                val r1 = callStatic("zts_init_from_storage", storagePath) as? Int ?: -1
                Log.i(TAG, "zts_init_from_storage=$r1")

                val r2 = callStatic("zts_node_start") as? Int ?: -1
                Log.i(TAG, "zts_node_start=$r2")
                if (r2 != ZTS_ERR_OK) throw Exception("zts_node_start gagal: code=$r2")

                Log.i(TAG, "Menunggu node online...")
                val t0 = System.currentTimeMillis()
                while (System.currentTimeMillis() - t0 < 15000) {
                    if (state == State.IDLE) return@Thread // dibatalkan
                    val online = callStatic("zts_node_is_online") as? Int ?: 0
                    if (online == 1) { Log.i(TAG, "Node online!"); break }
                    Thread.sleep(200)
                }
                if (callStatic("zts_node_is_online") as? Int != 1)
                    throw Exception("Timeout — node tidak online. Cek koneksi internet.")

                val r4 = callStatic("zts_net_join", netIdLong) as? Int ?: -1
                Log.i(TAG, "zts_net_join=$r4")
                if (r4 != ZTS_ERR_OK) throw Exception("zts_net_join gagal: code=$r4")

                Log.i(TAG, "Menunggu IP...")
                var ip = ""
                val t1 = System.currentTimeMillis()
                while (System.currentTimeMillis() - t1 < 25000) {
                    if (state == State.IDLE) return@Thread
                    val ready = callStatic("zts_net_transport_is_ready", netIdLong) as? Int ?: 0
                    if (ready == 1) {
                        val addr = callStatic("zts_addr_get_str", netIdLong, ZTS_AF_INET) as? String ?: ""
                        if (addr.isNotEmpty() && addr != "0.0.0.0" &&
                            addr != "null" && addr.contains(".")) {
                            ip = addr; break
                        }
                    }
                    Thread.sleep(300)
                }

                if (ip.isEmpty()) throw Exception(
                    "IP tidak diterima. Authorize node:\nmy.zerotier.com → Networks → Members → ✓ Auth"
                )

                assignedIp = ip
                state = State.READY
                Log.i(TAG, "ZeroTier READY! IP=$ip")
                onReady(ip)

            } catch (e: ExceptionInInitializerError) {
                state = State.ERROR
                onError("libzt.so tidak ditemukan: ${e.cause?.message ?: e.message}")
            } catch (e: ClassNotFoundException) {
                state = State.ERROR
                onError("libzt AAR tidak ditemukan di app/libs/")
            } catch (e: Exception) {
                state = State.ERROR
                onError(e.cause?.message ?: e.message ?: "Error tidak diketahui")
            }
        }.start()
    }

    fun shutdown(onDone: (() -> Unit)? = null) {
        if (state == State.IDLE || state == State.STOPPING) return
        state = State.STOPPING

        // Reset state dulu agar UI tidak menunggu
        val netId = currentNetworkId
        val cls   = ztNativeClass
        assignedIp       = ""
        currentNetworkId = 0L
        ztNativeClass    = null

        Thread {
            try {
                if (cls != null) {
                    // leave network dulu
                    if (netId != 0L) {
                        try {
                            val m = cls.methods.firstOrNull {
                                it.name == "zts_net_leave" && it.parameterTypes.size == 1
                            }
                            m?.invoke(null, netId)
                            Thread.sleep(500) // beri waktu leave selesai
                        } catch (e: Exception) {
                            Log.w(TAG, "leave error: ${e.message}")
                        }
                    }
                    // stop node
                    try {
                        val m = cls.methods.firstOrNull {
                            it.name == "zts_node_stop" && it.parameterTypes.isEmpty()
                        }
                        m?.invoke(null)
                        Thread.sleep(300) // beri waktu stop selesai
                    } catch (e: Exception) {
                        Log.w(TAG, "stop error: ${e.message}")
                    }
                    // free node resources
                    try {
                        val m = cls.methods.firstOrNull {
                            it.name == "zts_node_free" && it.parameterTypes.isEmpty()
                        }
                        m?.invoke(null)
                    } catch (e: Exception) {
                        Log.w(TAG, "free error: ${e.message}")
                    }
                }
                Log.i(TAG, "ZeroTier stopped")
            } catch (e: Exception) {
                Log.e(TAG, "Shutdown error: ${e.message}")
            } finally {
                state = State.IDLE
                onDone?.invoke()
            }
        }.start()
    }

    fun isReady()       = state == State.READY
    fun getAssignedIP() = assignedIp
}
