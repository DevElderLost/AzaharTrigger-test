#!/bin/bash
# fix_zt_dialog_clean.sh — Hapus tombol Buat Room dan Gabung Room
# dari ZeroTierDialog karena sudah ada di menu Multiplayer utama
#
# Cara pakai:
#   bash scripts/fix_zt_dialog_clean.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
DIALOGS_DIR="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/dialogs"
ZT_DIALOG="$DIALOGS_DIR/ZeroTierDialog.kt"
LAYOUT_DIR="$PROJECT_ROOT/src/android/app/src/main/res/layout"
ZT_LAYOUT="$LAYOUT_DIR/dialog_zerotier_native.xml"

[ -f "$ZT_DIALOG" ] || { echo "[ERROR] ZeroTierDialog.kt tidak ditemukan"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix: Bersihkan ZeroTierDialog — hanya setup koneksi"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Tulis ulang ZeroTierDialog.kt bersih tanpa Create/Join ────────
cat > "$ZT_DIALOG" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// ZeroTierDialog.kt — Dialog pengaturan koneksi ZeroTier
// Hanya berisi: input Network ID, Hubungkan, Putuskan, tampil IP
// Tombol Buat Room dan Gabung Room ada di menu Multiplayer utama

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

        // Pre-fill Network ID jika sudah disimpan
        ZeroTierManager.getNetworkId(context).let {
            if (it.isNotEmpty()) binding.networkId.setText(it)
        }
        updateStatusUI()

        // ── Tombol Hubungkan ─────────────────────────────────────
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
                        binding.assignedIp.text        = ip
                        binding.ipContainer.visibility = View.VISIBLE
                        binding.btnConnect.text        =
                            context.getString(R.string.zerotier_btn_reconnect)
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

        // ── Tombol Putuskan ──────────────────────────────────────
        binding.btnDisconnect.setOnClickListener {
            ZeroTierManager.shutdown()
            updateStatusUI()
            binding.ipContainer.visibility = View.GONE
            binding.btnConnect.text = context.getString(R.string.zerotier_btn_connect)
            Toast.makeText(
                context, R.string.zerotier_disconnected, Toast.LENGTH_SHORT
            ).show()
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
                binding.statusText.text =
                    context.getString(R.string.zerotier_status_idle)
                binding.ipContainer.visibility = View.GONE
                binding.btnConnect.text =
                    context.getString(R.string.zerotier_btn_connect)
            }
            ZeroTierManager.State.READY -> {
                val ip = ZeroTierManager.getAssignedIP()
                binding.statusText.text =
                    context.getString(R.string.zerotier_status_ready, ip)
                binding.assignedIp.text        = ip
                binding.ipContainer.visibility = View.VISIBLE
                binding.btnConnect.text        =
                    context.getString(R.string.zerotier_btn_reconnect)
            }
            ZeroTierManager.State.ERROR -> {
                binding.statusText.text =
                    context.getString(R.string.zerotier_status_error_generic)
                binding.ipContainer.visibility = View.GONE
            }
            else -> {}
        }
    }
}
EOF
echo "[OK] ZeroTierDialog.kt ditulis ulang (bersih tanpa Create/Join)"

# ── Update layout: hapus btnCreateRoom dan btnJoinRoom ────────────
if [ -f "$ZT_LAYOUT" ]; then
    python3 - "$ZT_LAYOUT" << 'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Hapus divider sebelum tombol room
content = re.sub(
    r'\s*<com\.google\.android\.material\.divider\.MaterialDivider[^/]*/>\s*\n\s*\n\s*<com\.google\.android\.material\.button\.MaterialButton\s[^>]*btnCreateRoom[^/]*/>\s*\n\s*\n\s*<com\.google\.android\.material\.button\.MaterialButton\s[^>]*btnJoinRoom[^/]*/>',
    '',
    content,
    flags=re.DOTALL
)

# Hapus juga jika ada tanpa divider
content = re.sub(
    r'\s*<com\.google\.android\.material\.button\.MaterialButton\s[^>]*btnCreateRoom[^/]*/>',
    '',
    content,
    flags=re.DOTALL
)
content = re.sub(
    r'\s*<com\.google\.android\.material\.button\.MaterialButton\s[^>]*btnJoinRoom[^/]*/>',
    '',
    content,
    flags=re.DOTALL
)

# Hapus divider yang tersisa di bagian bawah sebelum penutup
content = re.sub(
    r'\s*<com\.google\.android\.material\.divider\.MaterialDivider[^/]*/>\s*\n\s*\n\s*</LinearLayout>',
    '\n\n    </LinearLayout>',
    content
)

with open(path, 'w') as f:
    f.write(content)
print("[OK] dialog_zerotier_native.xml: btnCreateRoom dan btnJoinRoom dihapus")
PYEOF
else
    echo "[INFO] dialog_zerotier_native.xml tidak ditemukan, skip layout patch"
fi

echo ""
echo -e "\033[0;32m  Fix selesai!\033[0m"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: ZeroTierDialog bersih - hapus tombol Create/Join Room\""
echo "  git push origin DevElderLost-patch-4"
echo ""
