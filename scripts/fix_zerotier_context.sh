bash scripts/fix_zerotier_context.sh#!/bin/bash
# fix_zerotier_context.sh — Fix NetPlayManager.setRoomAddress()
# menerima Activity bukan Context.
# Solusi: cast Context ke Activity di ZeroTierDialog
#
# Cara pakai:
#   bash scripts/fix_zerotier_context.sh

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"

ZT_DIALOG=$(find "$PROJECT_ROOT/src" -name "ZeroTierDialog.kt" | head -1)
[ -n "$ZT_DIALOG" ] || error "ZeroTierDialog.kt tidak ditemukan"
info "ZeroTierDialog.kt: $ZT_DIALOG"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix ZeroTierDialog: Context → Activity cast"
echo "═══════════════════════════════════════════════════════"
echo ""

# Tulis ulang dengan CompatUtils.findActivity() untuk setRoomAddress
# tapi tetap pakai Context untuk BottomSheetDialog constructor
cat > "$ZT_DIALOG" << 'EOF'
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

    // BottomSheetDialog butuh Context, tapi NetPlayManager.setRoomAddress()
    // butuh Activity — pakai CompatUtils.findActivity() untuk konversi
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
                        // setRoomAddress butuh Activity
                        NetPlayManager.setRoomAddress(activity, ip)
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
            NetPlayManager.setRoomAddress(activity, ZeroTierManager.getAssignedIP())
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

success "ZeroTierDialog.kt ditulis ulang dengan CompatUtils.findActivity()"

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Fix selesai!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: ZeroTierDialog gunakan CompatUtils.findActivity() untuk setRoomAddress\""
echo "  git push origin DevElderLost-patch-4"
echo ""
