#!/usr/bin/env bash
# =============================================================================
# fix_combo_fragment_navigation.sh
#
# Fix ComboButtonSettingsFragment agar:
#   1. Tidak punya toolbar sendiri (pakai Activity toolbar)
#   2. Back arrow tidak terpotong status bar
#   3. Navigasi konsisten — Home nav = kembali ke HomeSettings
#   4. Window insets ditangani seperti HomeSettingsFragment
# =============================================================================

set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
die() { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

BASE=""
for c in "src/android" "app" "."; do
    [[ -f "$c/app/src/main/java/org/citra/citra_emu/fragments/HomeSettingsFragment.kt" ]] && BASE="$c" && break
done
[[ -n "$BASE" ]] || die "Tidak menemukan repo root."
ok "Base: $BASE"

APP="$BASE/app/src/main/java/org/citra/citra_emu"
RES="$BASE/app/src/main/res"
COMBO_FRAG="$APP/features/settings/ui/ComboButtonSettingsFragment.kt"
FRAG_LAYOUT="$RES/layout/fragment_combo_button_settings.xml"

# =============================================================================
# 1. Tulis ulang fragment_combo_button_settings.xml
#    Hapus MaterialToolbar — pakai activity toolbar
#    Tambah window insets handling via paddingTop pada ScrollView
# =============================================================================
echo ">>> Writing fragment_combo_button_settings.xml..."
cat > "$FRAG_LAYOUT" << 'XML'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/combo_settings_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical">

    <ScrollView
        android:id="@+id/combo_scroll_view"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:clipToPadding="false"
        android:paddingBottom="80dp">

        <LinearLayout
            android:id="@+id/combo_container"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:padding="8dp" />

    </ScrollView>

</LinearLayout>
XML
ok "fragment_combo_button_settings.xml rewritten (no toolbar)."

# =============================================================================
# 2. Tulis ulang ComboButtonSettingsFragment.kt
#    - Hapus toolbar manual, set judul via (activity as AppCompatActivity)
#    - Tambah WindowInsets handler sama seperti HomeSettingsFragment
#    - Navigasi: popBackStack() tetap untuk tombol back hardware/gesture
#    - Tambah onStop() untuk clear title saat keluar
# =============================================================================
echo ">>> Rewriting ComboButtonSettingsFragment.kt..."
cat > "$COMBO_FRAG" << 'KOTLIN'
// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

package org.citra.citra_emu.features.settings.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.MarginLayoutParams
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
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
 * Menggunakan Activity toolbar (tidak punya toolbar sendiri),
 * konsisten dengan pola HomeSettingsFragment.
 */
class ComboButtonSettingsFragment : Fragment() {

    private var _binding: FragmentComboButtonSettingsBinding? = null
    private val binding get() = _binding!!

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

        // Set judul via Activity toolbar — sama seperti fragment lain
        (activity as? AppCompatActivity)?.supportActionBar?.apply {
            title = getString(R.string.combo_button_settings)
            setDisplayHomeAsUpEnabled(true)
        }

        // Handle window insets — status bar + navigation bar
        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { v, windowInsets ->
            val barInsets    = windowInsets.getInsets(WindowInsetsCompat.Type.systemBars())
            val cutoutInsets = windowInsets.getInsets(WindowInsetsCompat.Type.displayCutout())

            val leftInset  = barInsets.left  + cutoutInsets.left
            val rightInset = barInsets.right + cutoutInsets.right
            val bottomInset = barInsets.bottom

            binding.comboScrollView.updatePadding(
                left   = leftInset,
                right  = rightInset,
                bottom = bottomInset + 80
            )

            val mlp = binding.comboScrollView.layoutParams as? MarginLayoutParams
            mlp?.topMargin = barInsets.top
            binding.comboScrollView.layoutParams = mlp

            windowInsets
        }

        // Inflate satu card per slot
        for (slot in 1..ComboButtonManager.COMBO_COUNT) {
            val cardBinding = ItemComboButtonBinding.inflate(
                layoutInflater, binding.comboContainer, true
            )
            bindSlot(cardBinding, slot)
        }
    }

    override fun onResume() {
        super.onResume()
        // Set judul setiap kali fragment resume (misal kembali dari back stack)
        (activity as? AppCompatActivity)?.supportActionBar?.apply {
            title = getString(R.string.combo_button_settings)
            setDisplayHomeAsUpEnabled(true)
        }
    }

    override fun onStop() {
        super.onStop()
        // Kembalikan judul ke default activity saat fragment hilang
        (activity as? AppCompatActivity)?.supportActionBar?.apply {
            setDisplayHomeAsUpEnabled(false)
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
}
KOTLIN
ok "ComboButtonSettingsFragment.kt rewritten."

echo ""
echo -e "${GREEN}Done!${NC}"
echo "git add -A && git commit -m 'fix(ui): use activity toolbar in ComboButtonSettingsFragment, fix insets and navigation' && git push"
