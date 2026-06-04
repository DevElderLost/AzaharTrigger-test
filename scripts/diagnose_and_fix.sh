#!/bin/bash
# diagnose_and_fix.sh — Diagnosa dan fix langsung ZeroTierDialog.kt
#
# Cara pakai:
#   bash scripts/diagnose_and_fix.sh

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Diagnosa ZeroTierDialog.kt"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Cari semua ZeroTierDialog.kt di project ─────────────────────────
info "Mencari semua ZeroTierDialog.kt..."
ALL_DIALOGS=$(find "$PROJECT_ROOT/src" -name "ZeroTierDialog.kt" 2>/dev/null)
if [ -z "$ALL_DIALOGS" ]; then
    error "ZeroTierDialog.kt tidak ditemukan sama sekali di project"
fi

echo "$ALL_DIALOGS" | while read f; do
    echo "  Ditemukan: $f"
    echo "  Baris 1-10:"
    head -10 "$f"
    echo "  ---"
    echo "  Cek Activity reference:"
    grep -n "Activity\|CompatUtils\|findActivity" "$f" | head -5 || echo "  (tidak ada)"
    echo ""
done

# ── Fix: tulis ulang semua ZeroTierDialog.kt yang ditemukan ─────────
info "Tulis ulang semua ZeroTierDialog.kt yang ditemukan..."

echo "$ALL_DIALOGS" | while read DIALOG_FILE; do
    echo "  Fixing: $DIALOG_FILE"
    cat > "$DIALOG_FILE" << 'EOF'
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
                binding.statusText.text =
                    context.getString(R.string.zerotier_status_idle)
                binding.btnCreateRoom.isEnabled = false
                binding.btnJoinRoom.isEnabled   = false
                binding.ipContainer.visibility  = View.GONE
            }
            ZeroTierManager.State.READY -> {
                val ip = ZeroTierManager.getAssignedIP()
                binding.statusText.text =
                    context.getString(R.string.zerotier_status_ready, ip)
                binding.assignedIp.text         = ip
                binding.ipContainer.visibility  = View.VISIBLE
                binding.btnCreateRoom.isEnabled = true
                binding.btnJoinRoom.isEnabled   = true
            }
            ZeroTierManager.State.ERROR -> {
                binding.statusText.text =
                    context.getString(R.string.zerotier_status_error_generic)
                binding.btnCreateRoom.isEnabled = false
                binding.btnJoinRoom.isEnabled   = false
            }
            else -> {}
        }
    }
}
EOF
    echo "  Selesai: $DIALOG_FILE"
done

success "Semua ZeroTierDialog.kt ditulis ulang"

# ── Verifikasi tidak ada Activity reference lagi ────────────────────
echo ""
info "Verifikasi..."
echo "$ALL_DIALOGS" | while read f; do
    if grep -q "Activity\|CompatUtils\|findActivity" "$f" 2>/dev/null; then
        warn "Masih ada Activity reference di: $f"
        grep -n "Activity\|CompatUtils\|findActivity" "$f"
    else
        success "OK — tidak ada Activity reference: $f"
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Fix selesai!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: tulis ulang ZeroTierDialog.kt tanpa Activity reference\""
echo "  git push origin DevElderLost-patch-4"
echo ""
