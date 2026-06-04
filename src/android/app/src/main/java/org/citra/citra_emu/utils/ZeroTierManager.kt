// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
package org.citra.citra_emu.utils

import android.content.Context
import android.util.Log
import java.io.File

object ZeroTierManager {
    private const val TAG       = "ZeroTierManager"
    private const val PREFS_KEY = "zerotier_prefs"
    private const val KEY_NET   = "zt_network_id"

    enum class State { IDLE, STARTING, READY, ERROR }

    @Volatile var state: State = State.IDLE
        private set

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
        if (state == State.READY) { onReady(getAssignedIP()); return }
        if (state == State.STARTING) { onError("Sedang dalam proses inisialisasi"); return }
        state = State.STARTING

        val storagePath = try {
            File(context.filesDir, "zt/$networkId").apply { mkdirs() }.absolutePath
        } catch (e: Exception) {
            state = State.ERROR
            onError("Gagal membuat folder storage: ${e.message}")
            return
        }

        Thread {
            try {
                Log.i(TAG, "Init ZeroTier network=$networkId path=$storagePath")
                val code = NetPlayManager.ztInit(storagePath, networkId)
                if (code == 0) {
                    val ip = NetPlayManager.ztGetAssignedIP()
                    if (ip.isNullOrEmpty()) {
                        state = State.ERROR
                        onError("IP tidak diterima dari ZeroTier")
                    } else {
                        state = State.READY
                        Log.i(TAG, "ZeroTier ready IP=$ip")
                        onReady(ip)
                    }
                } else {
                    state = State.ERROR
                    val msg = when (code) {
                        1    -> "Sudah berjalan"
                        2    -> "Gagal inisialisasi — class ZeroTier tidak ditemukan di AAR"
                        3    -> "Gagal join — periksa Network ID"
                        4    -> "Node belum diauthorize di my.zerotier.com"
                        5    -> "Timeout menunggu node online"
                        else -> "Error tidak diketahui (code $code)"
                    }
                    Log.e(TAG, "ZeroTier error: $msg")
                    onError(msg)
                }
            } catch (e: UnsatisfiedLinkError) {
                // Native library tidak ter-load
                state = State.ERROR
                val msg = "Native library ZeroTier tidak ditemukan. Pastikan libzt-release.aar sudah ditambahkan."
                Log.e(TAG, msg, e)
                onError(msg)
            } catch (e: Exception) {
                state = State.ERROR
                val msg = "Crash: ${e.javaClass.simpleName}: ${e.message}"
                Log.e(TAG, msg, e)
                onError(msg)
            }
        }.start()
    }

    fun shutdown() {
        if (state == State.IDLE) return
        try {
            NetPlayManager.ztShutdown()
        } catch (e: Exception) {
            Log.e(TAG, "Shutdown error: ${e.message}", e)
        }
        state = State.IDLE
        Log.i(TAG, "ZeroTier shutdown")
    }

    fun isReady()       = state == State.READY
    fun getAssignedIP() = if (isReady()) NetPlayManager.ztGetAssignedIP() ?: "" else ""
}
