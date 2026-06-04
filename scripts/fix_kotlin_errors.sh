#!/bin/bash
# fix_kotlin_errors.sh — Tulis ulang ZeroTierManager.kt, ZeroTierDialog.kt
# dan tambah zt* JNI ke NetPlayManager.kt
#
# Cara pakai:
#   bash scripts/fix_kotlin_errors.sh

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
KOTLIN_BASE="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu"
DIALOGS_DIR="$KOTLIN_BASE/dialogs"
UTILS_DIR="$KOTLIN_BASE/utils"

[ -d "$DIALOGS_DIR" ] || error "Folder dialogs tidak ditemukan: $DIALOGS_DIR"
[ -d "$UTILS_DIR"   ] || error "Folder utils tidak ditemukan: $UTILS_DIR"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix Kotlin ZeroTier — Tulis Ulang File"
echo "═══════════════════════════════════════════════════════"
echo ""

# ════════════════════════════════════════════════════════════════════
# FIX 1: Tulis ulang ZeroTierManager.kt
# Menggunakan NetPlayManager.ztXxx() yang benar
# ════════════════════════════════════════════════════════════════════
info "Fix 1/3: Tulis ulang ZeroTierManager.kt..."

cat > "$UTILS_DIR/ZeroTierManager.kt" << 'EOF'
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
        val storagePath = File(context.filesDir, "zt/$networkId").apply { mkdirs() }.absolutePath
        Thread {
            Log.i(TAG, "Init ZeroTier network=$networkId")
            val code = NetPlayManager.ztInit(storagePath, networkId)
            if (code == 0) {
                val ip = NetPlayManager.ztGetAssignedIP()
                state = State.READY
                Log.i(TAG, "ZeroTier ready IP=$ip")
                onReady(ip)
            } else {
                state = State.ERROR
                val msg = when (code) {
                    1    -> "Sudah berjalan"
                    2    -> "Gagal inisialisasi node"
                    3    -> "Gagal join — periksa Network ID"
                    4    -> "Node belum diauthorize di my.zerotier.com"
                    5    -> "Timeout menunggu node online"
                    else -> "Error tidak diketahui (code $code)"
                }
                Log.e(TAG, "ZeroTier error: $msg")
                onError(msg)
            }
        }.start()
    }

    fun shutdown() {
        if (state == State.IDLE) return
        NetPlayManager.ztShutdown()
        state = State.IDLE
        Log.i(TAG, "ZeroTier shutdown")
    }

    fun isReady()       = state == State.READY
    fun getAssignedIP() = if (isReady()) NetPlayManager.ztGetAssignedIP() else ""
}
EOF
success "ZeroTierManager.kt ditulis ulang"

# ════════════════════════════════════════════════════════════════════
# FIX 2: Tulis ulang ZeroTierDialog.kt
# Pakai Context langsung — TIDAK pakai CompatUtils.findActivity()
# karena BottomSheetDialog butuh Context, bukan Activity
# ════════════════════════════════════════════════════════════════════
info "Fix 2/3: Tulis ulang ZeroTierDialog.kt..."

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
import org.citra.citra_emu.utils.NetPlayManager
import org.citra.citra_emu.utils.ZeroTierManager

class ZeroTierDialog(context: Context) : BottomSheetDialog(context) {
    private lateinit var binding: DialogZerotierNativeBinding

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
        updateStatusUI()

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

            ZeroTierManager.init(
                context   = context,
                networkId = networkId,
                onReady   = { ip ->
                    binding.root.post {
                        setLoading(false)
                        binding.statusText.text =
                            context.getString(R.string.zerotier_status_ready, ip)
                        binding.assignedIp.text         = ip
                        binding.ipContainer.visibility  = View.VISIBLE
                        binding.btnConnect.text         =
                            context.getString(R.string.zerotier_btn_reconnect)
                        binding.btnCreateRoom.isEnabled = true
                        binding.btnJoinRoom.isEnabled   = true
                        NetPlayManager.setRoomAddress(context, ip)
                    }
                },
                onError = { msg ->
                    binding.root.post {
                        setLoading(false)
                        binding.statusText.text =
                            context.getString(R.string.zerotier_status_error, msg)
                        Toast.makeText(context, msg, Toast.LENGTH_LONG).show()
                    }
                }
            )
        }

        binding.btnDisconnect.setOnClickListener {
            ZeroTierManager.shutdown()
            updateStatusUI()
            binding.ipContainer.visibility  = View.GONE
            binding.btnCreateRoom.isEnabled = false
            binding.btnJoinRoom.isEnabled   = false
            Toast.makeText(context, R.string.zerotier_disconnected, Toast.LENGTH_SHORT).show()
        }

        binding.btnCreateRoom.setOnClickListener {
            if (!ZeroTierManager.isReady()) return@setOnClickListener
            NetPlayManager.setRoomAddress(context, ZeroTierManager.getAssignedIP())
            dismiss()
            NetPlayDialog(context).show()
        }

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

    private fun updateStatusUI() {
        when (ZeroTierManager.state) {
            ZeroTierManager.State.IDLE -> {
                binding.statusText.text         =
                    context.getString(R.string.zerotier_status_idle)
                binding.btnCreateRoom.isEnabled = false
                binding.btnJoinRoom.isEnabled   = false
                binding.ipContainer.visibility  = View.GONE
            }
            ZeroTierManager.State.READY -> {
                val ip = ZeroTierManager.getAssignedIP()
                binding.statusText.text         =
                    context.getString(R.string.zerotier_status_ready, ip)
                binding.assignedIp.text         = ip
                binding.ipContainer.visibility  = View.VISIBLE
                binding.btnCreateRoom.isEnabled = true
                binding.btnJoinRoom.isEnabled   = true
            }
            ZeroTierManager.State.ERROR -> {
                binding.statusText.text         =
                    context.getString(R.string.zerotier_status_error_generic)
                binding.btnCreateRoom.isEnabled = false
                binding.btnJoinRoom.isEnabled   = false
            }
            else -> {}
        }
    }
}
EOF
success "ZeroTierDialog.kt ditulis ulang"

# ════════════════════════════════════════════════════════════════════
# FIX 3: NetPlayManager.kt — tambah zt* JNI declarations
# ════════════════════════════════════════════════════════════════════
info "Fix 3/3: Tambah zt* JNI ke NetPlayManager.kt..."

NETPLAY_MGR=$(find "$PROJECT_ROOT/src" -name "NetPlayManager.kt" | head -1)
[ -n "$NETPLAY_MGR" ] || error "NetPlayManager.kt tidak ditemukan"
info "NetPlayManager.kt: $NETPLAY_MGR"

if grep -q "ztInit" "$NETPLAY_MGR"; then
    success "ztInit sudah ada di NetPlayManager.kt, skip"
else
    PATCH_PY=$(mktemp /tmp/fix_netplay_XXXXXX.py)
    cat > "$PATCH_PY" << 'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

zt_jni = """\n
        // ── ZeroTier JNI ─────────────────────────────────────────────
        @JvmStatic external fun ztInit(storagePath: String, networkIdHex: String): Int
        @JvmStatic external fun ztShutdown()
        @JvmStatic external fun ztGetAssignedIP(): String
        @JvmStatic external fun ztIsReady(): Boolean"""

# Sisipkan setelah @JvmStatic external fun terakhir yang ada
matches = list(re.finditer(r'@JvmStatic external fun \w+[^\n]*\n', content))
if matches:
    pos = matches[-1].end()
    content = content[:pos] + zt_jni + "\n" + content[pos:]
    with open(path, 'w') as f:
        f.write(content)
    print("  4 fungsi zt* berhasil ditambahkan")
else:
    # Fallback: sisipkan sebelum closing brace terakhir
    last_brace = content.rfind('\n}')
    if last_brace != -1:
        content = content[:last_brace] + zt_jni + "\n" + content[last_brace:]
        with open(path, 'w') as f:
            f.write(content)
        print("  4 fungsi zt* ditambahkan (fallback)")
    else:
        print("  ERROR: Tidak bisa menemukan titik insert")
        sys.exit(1)
PYEOF
    python3 "$PATCH_PY" "$NETPLAY_MGR"
    rm -f "$PATCH_PY"
    success "NetPlayManager.kt: tambah ztInit/ztShutdown/ztGetAssignedIP/ztIsReady"
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Fix selesai!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Langkah selanjutnya:"
echo "  git add ."
echo "  git commit -m \"fix: tulis ulang ZeroTierDialog+Manager, tambah zt* JNI\""
echo "  git push origin DevElderLost-patch-4"
echo ""
