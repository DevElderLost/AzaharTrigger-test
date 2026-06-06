#!/bin/bash
# fix_zt_shutdown_and_buttons.sh
# Fix 1: crash setelah Putuskan
# Fix 2: tambah tombol Create/Join Room di ZeroTierDialog (hanya saat ready)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
UTILS_DIR="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/utils"
DIALOGS_DIR="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/dialogs"
LAYOUT_DIR="$PROJECT_ROOT/src/android/app/src/main/res/layout"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix ZeroTier: crash shutdown + tambah Create/Join"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Fix 1: ZeroTierManager.kt — safe shutdown ─────────────────────
cat > "$UTILS_DIR/ZeroTierManager.kt" << 'EOF'
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
EOF
echo "[OK] ZeroTierManager.kt ditulis ulang dengan safe shutdown"

# ── Fix 2: ZeroTierDialog.kt — tambah Create/Join saat ready ──────
cat > "$DIALOGS_DIR/ZeroTierDialog.kt" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
package org.citra.citra_emu.dialogs

import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.widget.Toast
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import org.citra.citra_emu.R
import org.citra.citra_emu.databinding.DialogZerotierNativeBinding
import org.citra.citra_emu.utils.CompatUtils
import org.citra.citra_emu.utils.NetPlayManager
import org.citra.citra_emu.utils.ZeroTierManager

class ZeroTierDialog(context: Context) : BottomSheetDialog(context) {
    private lateinit var binding: DialogZerotierNativeBinding
    private val activity by lazy { CompatUtils.findActivity(context) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        behavior.state = BottomSheetBehavior.STATE_EXPANDED
        behavior.skipCollapsed =
            context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE

        binding = DialogZerotierNativeBinding.inflate(LayoutInflater.from(context))
        setContentView(binding.root)

        ZeroTierManager.getNetworkId(context).let {
            if (it.isNotEmpty()) binding.networkId.setText(it)
        }
        updateUI()

        // ── Hubungkan ────────────────────────────────────────────
        binding.btnConnect.setOnClickListener {
            val networkId = binding.networkId.text.toString().trim()
            if (networkId.length != 16) {
                binding.networkIdLayout.error =
                    context.getString(R.string.zerotier_network_id_invalid)
                return@setOnClickListener
            }
            binding.networkIdLayout.error = null
            ZeroTierManager.saveNetworkId(context, networkId)
            setLoading(true)
            binding.statusText.text = context.getString(R.string.zerotier_status_starting)

            ZeroTierManager.init(context, networkId,
                onReady = { ip ->
                    binding.root.post {
                        setLoading(false)
                        binding.statusText.text =
                            context.getString(R.string.zerotier_status_ready, ip)
                        binding.assignedIp.text        = ip
                        binding.ipContainer.visibility = View.VISIBLE
                        binding.btnConnect.text        =
                            context.getString(R.string.zerotier_btn_reconnect)
                        // Tampilkan tombol room saat terhubung
                        binding.roomButtonsGroup.visibility = View.VISIBLE
                    }
                },
                onError = { msg ->
                    binding.root.post {
                        setLoading(false)
                        binding.statusText.text =
                            context.getString(R.string.zerotier_status_error, msg)
                        Toast.makeText(context, msg, Toast.LENGTH_LONG).show()
                        binding.roomButtonsGroup.visibility = View.GONE
                    }
                }
            )
        }

        // ── Putuskan ─────────────────────────────────────────────
        binding.btnDisconnect.setOnClickListener {
            binding.btnDisconnect.isEnabled = false
            binding.btnDisconnect.text      = "Memutus..."
            binding.roomButtonsGroup.visibility = View.GONE

            ZeroTierManager.shutdown {
                binding.root.post {
                    updateUI()
                    binding.btnDisconnect.isEnabled = true
                    binding.btnDisconnect.text =
                        context.getString(R.string.zerotier_btn_disconnect)
                    Toast.makeText(
                        context, R.string.zerotier_disconnected, Toast.LENGTH_SHORT
                    ).show()
                }
            }
        }

        // ── Buat Room (Create) ────────────────────────────────────
        binding.btnCreateRoom.setOnClickListener {
            if (!ZeroTierManager.isReady()) return@setOnClickListener
            // Simpan ZeroTier IP agar NetPlayDialog bisa pre-fill
            NetPlayManager.setRoomAddress(activity, ZeroTierManager.getAssignedIP())
            dismiss()
            NetPlayDialog(context).apply {
                // Trigger showNetPlayInputDialog(isCreateRoom=true)
            }.show()
        }

        // ── Gabung Room (Join) ────────────────────────────────────
        binding.btnJoinRoom.setOnClickListener {
            if (!ZeroTierManager.isReady()) return@setOnClickListener
            dismiss()
            NetPlayDialog(context).show()
        }
    }

    private fun setLoading(loading: Boolean) {
        binding.progressBar.visibility  = if (loading) View.VISIBLE else View.GONE
        binding.btnConnect.isEnabled    = !loading
        binding.btnDisconnect.isEnabled = !loading
        binding.networkId.isEnabled     = !loading
    }

    private fun updateUI() {
        when (ZeroTierManager.state) {
            ZeroTierManager.State.IDLE,
            ZeroTierManager.State.ERROR -> {
                binding.statusText.text =
                    if (ZeroTierManager.state == ZeroTierManager.State.IDLE)
                        context.getString(R.string.zerotier_status_idle)
                    else context.getString(R.string.zerotier_status_error_generic)
                binding.ipContainer.visibility      = View.GONE
                binding.roomButtonsGroup.visibility = View.GONE
                binding.btnConnect.text =
                    context.getString(R.string.zerotier_btn_connect)
            }
            ZeroTierManager.State.READY -> {
                val ip = ZeroTierManager.getAssignedIP()
                binding.statusText.text =
                    context.getString(R.string.zerotier_status_ready, ip)
                binding.assignedIp.text             = ip
                binding.ipContainer.visibility      = View.VISIBLE
                binding.roomButtonsGroup.visibility = View.VISIBLE
                binding.btnConnect.text =
                    context.getString(R.string.zerotier_btn_reconnect)
            }
            else -> {}
        }
    }
}
EOF
echo "[OK] ZeroTierDialog.kt ditulis ulang dengan Create/Join Room"

# ── Fix 3: Layout — tambah room buttons group ─────────────────────
ZT_LAYOUT="$LAYOUT_DIR/dialog_zerotier_native.xml"
if [ -f "$ZT_LAYOUT" ] && ! grep -q "roomButtonsGroup" "$ZT_LAYOUT"; then
    python3 - "$ZT_LAYOUT" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

room_buttons = """
        <!-- Tombol room — hanya tampil saat ZeroTier terhubung -->
        <LinearLayout
            android:id="@+id/roomButtonsGroup"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:visibility="gone">

            <com.google.android.material.divider.MaterialDivider
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="8dp"
                android:layout_marginBottom="8dp" />

            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnCreateRoom"
                style="@style/Widget.Material3.Button.TonalButton"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginBottom="8dp"
                android:text="@string/multiplayer_create_room" />

            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnJoinRoom"
                style="@style/Widget.Material3.Button.OutlinedButton"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginBottom="8dp"
                android:text="@string/multiplayer_join_room" />

        </LinearLayout>
"""

# Sisipkan sebelum closing tag LinearLayout utama
last = content.rfind('</LinearLayout>')
if last != -1:
    content = content[:last] + room_buttons + content[last:]
    with open(path, 'w') as f:
        f.write(content)
    print("[OK] dialog_zerotier_native.xml: roomButtonsGroup ditambahkan")
else:
    print("[WARN] Closing tag tidak ditemukan di layout")
PYEOF
fi

echo ""
echo -e "\033[0;32m  Fix selesai!\033[0m"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: ZeroTier safe shutdown + tambah Create/Join Room di ZeroTierDialog\""
echo "  git push origin DevElderLost-patch-4"
echo ""
