// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

package org.citra.citra_emu.features.settings.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import org.citra.citra_emu.viewmodel.HomeViewModel
import androidx.navigation.fragment.findNavController
import com.google.android.material.chip.Chip
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.transition.MaterialSharedAxis
import org.citra.citra_emu.R
import org.citra.citra_emu.databinding.FragmentComboButtonSettingsBinding
import org.citra.citra_emu.databinding.ItemComboButtonBinding
import org.citra.citra_emu.overlay.ComboButtonManager

class ComboButtonSettingsFragment : Fragment() {

    private var _binding: FragmentComboButtonSettingsBinding? = null
    private val binding get() = _binding!!

    private val homeViewModel: HomeViewModel by activityViewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enterTransition  = MaterialSharedAxis(MaterialSharedAxis.X, true)
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

        // Setup toolbar
        binding.toolbar.apply {
            title = getString(R.string.combo_button_settings)
            setNavigationIcon(R.drawable.ic_back)
            setNavigationOnClickListener { findNavController().popBackStack() }
        }

        // Handle status bar inset — hanya tambah padding top pada toolbar
        ViewCompat.setOnApplyWindowInsetsListener(binding.toolbar) { v, insets ->
            val statusBar = insets.getInsets(WindowInsetsCompat.Type.statusBars())
            v.setPadding(v.paddingLeft, statusBar.top, v.paddingRight, v.paddingBottom)
            insets
        }

        // Inflate satu card per slot
        for (slot in 1..ComboButtonManager.COMBO_COUNT) {
            val cardBinding = ItemComboButtonBinding.inflate(
                layoutInflater, binding.comboContainer, true
            )
            bindSlot(cardBinding, slot)
        }
    }

    private fun bindSlot(card: ItemComboButtonBinding, slot: Int) {
        card.comboTitle.text = "Combo $slot"

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
                                val current = ComboButtonManager
                                    .getButtonsForSlot(slot).toMutableList()
                                current.remove(id)
                                ComboButtonManager.setButtonsForSlot(slot, current)
                                refreshChips()
                            }
                        }
                    )
                }
            }
        }

        refreshChips()

        card.btnEdit.setOnClickListener {
            showPickerDialog(slot) { refreshChips() }
        }
    }

    private fun showPickerDialog(slot: Int, onDone: () -> Unit) {
        val assignable = ComboButtonManager.assignableButtons
        val names      = assignable.map { it.first }.toTypedArray()
        val ids        = assignable.map { it.second }
        val selected   = ComboButtonManager.getButtonsForSlot(slot).toMutableSet()
        val checked    = BooleanArray(names.size) { i -> ids[i] in selected }

        MaterialAlertDialogBuilder(requireContext())
            .setTitle("Assign buttons — Combo $slot")
            .setMultiChoiceItems(names, checked) { _, which, isChecked ->
                val id = ids[which]
                if (isChecked) {
                    if (selected.size >= ComboButtonManager.MAX_BUTTONS_PER_COMBO) {
                        checked[which] = false
                        Toast.makeText(
                            requireContext(),
                            getString(R.string.combo_button_max_exceeded,
                                ComboButtonManager.MAX_BUTTONS_PER_COMBO),
                            Toast.LENGTH_SHORT
                        ).show()
                    } else selected.add(id)
                } else selected.remove(id)
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

    override fun onStart() {
        super.onStart()
        // Sembunyikan bottom navigation — sama seperti fragment settings lain
        homeViewModel.setNavigationVisibility(visible = false, animated = true)
        homeViewModel.setStatusBarShadeVisibility(visible = false)
    }

    override fun onStop() {
        super.onStop()
        // Tampilkan kembali saat keluar dari fragment ini
        homeViewModel.setNavigationVisibility(visible = true, animated = true)
        homeViewModel.setStatusBarShadeVisibility(visible = true)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
