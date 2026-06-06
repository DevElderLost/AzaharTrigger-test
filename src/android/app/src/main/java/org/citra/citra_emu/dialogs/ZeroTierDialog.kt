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
