// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

package org.citra.citra_emu.features.settings.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.core.widget.doOnTextChanged
import android.widget.SeekBar
import androidx.fragment.app.Fragment
import androidx.navigation.fragment.findNavController
import com.google.android.material.chip.Chip
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.transition.MaterialSharedAxis
import org.citra.citra_emu.R
import org.citra.citra_emu.databinding.FragmentComboButtonSettingsBinding
import org.citra.citra_emu.databinding.ItemComboButtonBinding
import org.citra.citra_emu.overlay.ComboButtonManager

/**
 * Fragment pengaturan Combo Buttons 1–5.
 * UI menggunakan Material Design konsisten dengan tampilan Azahar lainnya.
 * Toggle show/hide combo di overlay dilakukan melalui "Toggle Controls"
 * di Overlay Options saat emulasi berjalan (buttonToggle20–24).
 */
class ComboButtonSettingsFragment : Fragment() {

    private var _binding: FragmentComboButtonSettingsBinding? = null
    private val binding get() = _binding!!

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enterTransition = MaterialSharedAxis(MaterialSharedAxis.X, true)
        returnTransition = MaterialSharedAxis(MaterialSharedAxis.X, false)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentComboButtonSettingsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        // Setup toolbar dengan back navigation
        binding.toolbar.apply {
            title = getString(R.string.combo_button_settings)
            setNavigationIcon(R.drawable.ic_back)
            setNavigationOnClickListener { findNavController().popBackStack() }
        }

        // Inflate satu card per slot combo
        for (slot in 1..ComboButtonManager.COMBO_COUNT) {
            val cardBinding = ItemComboButtonBinding.inflate(
                layoutInflater, binding.comboContainer, true
            )
            bindSlot(cardBinding, slot)
        }
    }

    private fun bindSlot(card: ItemComboButtonBinding, slot: Int) {
        // Judul slot
        card.comboTitle.text = "Combo $slot"

        // Label field — isi dengan label tersimpan kalau bukan auto
        val autoLabel = ComboButtonManager.autoLabel(slot)
        val savedLabel = ComboButtonManager.getLabelForSlot(slot)
        if (savedLabel != autoLabel) {
            card.labelEditText.setText(savedLabel)
        }
        card.labelInputLayout.hint = "Label (leave blank for auto: \"$autoLabel\")"

        card.labelEditText.doOnTextChanged { text, _, _, _ ->
            ComboButtonManager.setLabelForSlot(slot, text.toString())
            // Update hint auto-label secara live
            card.labelInputLayout.hint =
                "Label (kosong = auto: \"${ComboButtonManager.autoLabel(slot)}\")"
        }

        // Render chips
        fun refreshChips() {
            card.chipGroup.removeAllViews()
            val assigned = ComboButtonManager.getButtonsForSlot(slot)
            if (assigned.isEmpty()) {
                card.chipGroup.addView(
                    Chip(requireContext()).apply {
                        text = getString(R.string.combo_button_none_assigned)
                        isEnabled = false
                    }
                )
            } else {
                assigned.forEach { id ->
                    card.chipGroup.addView(
                        Chip(requireContext()).apply {
                            text = ComboButtonManager.buttonShortName(id)
                            isCloseIconVisible = true
                            setOnCloseIconClickListener {
                                val current = ComboButtonManager.getButtonsForSlot(slot).toMutableList()
                                current.remove(id)
                                ComboButtonManager.setButtonsForSlot(slot, current)
                                refreshChips()
                                // Update hint
                                card.labelInputLayout.hint =
                                    "Label (kosong = auto: \"${ComboButtonManager.autoLabel(slot)}\")"
                            }
                        }
                    )
                }
            }
        }

        refreshChips()

        // Tombol edit — buka dialog multi-pilih
        card.btnEdit.setOnClickListener {
            showPickerDialog(slot) { refreshChips() }
        }

        // Scale seekbar — baca nilai tersimpan, default 50
        val prefs = getPreferences()
        val savedScale = prefs.getInt(scaleKey(slot), 50)
        card.comboScaleSeekbar.progress = savedScale
        card.comboScaleValue.text = savedScale.toString()

        card.comboScaleSeekbar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                card.comboScaleValue.text = progress.toString()
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {
                // Simpan ke prefs dengan key yang sama dengan InputOverlay
                prefs.edit()
                    .putInt(scaleKey(slot), card.comboScaleSeekbar.progress)
                    .apply()
                // Refresh overlay supaya langsung terlihat perubahannya
                activity?.findViewById<org.citra.citra_emu.overlay.InputOverlay>(
                    org.citra.citra_emu.R.id.surface_input_overlay
                )?.refreshControls()
            }
        })
    }

    private fun showPickerDialog(slot: Int, onDone: () -> Unit) {
        val assignable = ComboButtonManager.assignableButtons
        val names      = assignable.map { it.first }.toTypedArray()
        val ids        = assignable.map { it.second }
        val selected   = ComboButtonManager.getButtonsForSlot(slot).toMutableSet()
        val checked    = BooleanArray(names.size) { i -> ids[i] in selected }

        MaterialAlertDialogBuilder(requireContext())
            .setTitle("Assign buttons — Combo $slot (max ${ComboButtonManager.MAX_BUTTONS_PER_COMBO})")
            .setMultiChoiceItems(names, checked) { _, which, isChecked ->
                val id = ids[which]
                if (isChecked) {
                    if (selected.size >= ComboButtonManager.MAX_BUTTONS_PER_COMBO) {
                        checked[which] = false
                        Toast.makeText(
                            requireContext(),
                            getString(
                                R.string.combo_button_max_exceeded,
                                ComboButtonManager.MAX_BUTTONS_PER_COMBO
                            ),
                            Toast.LENGTH_SHORT
                        ).show()
                    } else {
                        selected.add(id)
                    }
                } else {
                    selected.remove(id)
                }
            }
            .setPositiveButton(android.R.string.ok) { _, _ ->
                ComboButtonManager.setButtonsForSlot(slot, selected.toList())
                onDone()
            }
            .setNeutralButton(R.string.combo_clear_all) { _, _ ->
                ComboButtonManager.setButtonsForSlot(slot, emptyList())
                onDone()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    // Key yang dipakai InputOverlay untuk scale per-button
    // Format: "controlScale-$buttonId"  (sama dengan button lain)
    private fun scaleKey(slot: Int): String {
        val id = ComboButtonManager.COMBO_IDS[slot - 1]
        return "controlScale-$id"
    }

    private fun getPreferences() =
        androidx.preference.PreferenceManager.getDefaultSharedPreferences(requireContext())
}
