#!/usr/bin/env bash
# =============================================================================
# fix_combo_settings_ui.sh
#
# Tulis ulang ComboButtonSettingsFragment dengan UI Material Design
# yang konsisten dengan style Azahar (ViewBinding, MaterialAlertDialog,
# RecyclerView, tidak ada switch "Show on overlay").
#
# Jalankan dari ROOT repo:
#   bash scripts/fix_combo_settings_ui.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

# Auto-detect base path
BASE=""
for candidate in "src/android" "app" "."; do
    if [[ -f "$candidate/app/src/main/java/org/citra/citra_emu/fragments/HomeSettingsFragment.kt" ]]; then
        BASE="$candidate"; break
    fi
done
[[ -n "$BASE" ]] || die "Tidak bisa menemukan HomeSettingsFragment.kt — jalankan dari root repo."
ok "Base path: $BASE"

APP="$BASE/app/src/main/java/org/citra/citra_emu"
RES="$BASE/app/src/main/res"
SETTINGS_UI="$APP/features/settings/ui"
LAYOUT_DIR="$RES/layout"

echo ""
echo "============================================="
echo "  Fix Combo Settings UI — Material Design    "
echo "============================================="
echo ""

# =============================================================================
# 1. Layout XML: fragment_combo_button_settings.xml
# =============================================================================
echo ">>> Writing layout XML..."
mkdir -p "$LAYOUT_DIR"

cat > "$LAYOUT_DIR/fragment_combo_button_settings.xml" << 'XML'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical">

    <com.google.android.material.appbar.MaterialToolbar
        android:id="@+id/toolbar"
        android:layout_width="match_parent"
        android:layout_height="?attr/actionBarSize"
        android:elevation="4dp" />

    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="match_parent">

        <LinearLayout
            android:id="@+id/combo_container"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:padding="8dp" />

    </ScrollView>

</LinearLayout>
XML
ok "fragment_combo_button_settings.xml dibuat."

# =============================================================================
# 2. Layout XML: item_combo_button.xml  (satu card per slot)
# =============================================================================
cat > "$LAYOUT_DIR/item_combo_button.xml" << 'XML'
<?xml version="1.0" encoding="utf-8"?>
<com.google.android.material.card.MaterialCardView
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:layout_margin="8dp"
    app:cardCornerRadius="12dp"
    app:cardElevation="2dp">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:padding="16dp">

        <!-- Header: Judul slot -->
        <TextView
            android:id="@+id/combo_title"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:textAppearance="?attr/textAppearanceTitleMedium"
            android:textStyle="bold"
            android:paddingBottom="8dp" />

        <!-- Label field -->
        <com.google.android.material.textfield.TextInputLayout
            android:id="@+id/label_input_layout"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:hint="Label (kosong = auto)"
            style="@style/Widget.MaterialComponents.TextInputLayout.OutlinedBox"
            android:layout_marginBottom="12dp">

            <com.google.android.material.textfield.TextInputEditText
                android:id="@+id/label_edit_text"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:inputType="text"
                android:maxLines="1" />

        </com.google.android.material.textfield.TextInputLayout>

        <!-- Assigned buttons label -->
        <TextView
            android:id="@+id/assigned_label"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Tombol yang diassign:"
            android:textAppearance="?attr/textAppearanceLabelMedium"
            android:paddingBottom="4dp" />

        <!-- Chips assigned buttons -->
        <com.google.android.material.chip.ChipGroup
            android:id="@+id/chip_group"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="12dp" />

        <!-- Edit button -->
        <com.google.android.material.button.MaterialButton
            android:id="@+id/btn_edit"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Pilih Tombol..."
            style="@style/Widget.MaterialComponents.Button.OutlinedButton" />

    </LinearLayout>

</com.google.android.material.card.MaterialCardView>
XML
ok "item_combo_button.xml dibuat."

# =============================================================================
# 3. ComboButtonSettingsFragment.kt — tulis ulang dengan ViewBinding
# =============================================================================
echo ">>> Menulis ulang ComboButtonSettingsFragment.kt..."

FRAG_FILE="$SETTINGS_UI/ComboButtonSettingsFragment.kt"

cat > "$FRAG_FILE" << 'KOTLIN'
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
            setNavigationIcon(R.drawable.ic_arrow_back)
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
        card.labelInputLayout.hint = "Label (kosong = auto: \"$autoLabel\")"

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
    }

    private fun showPickerDialog(slot: Int, onDone: () -> Unit) {
        val assignable = ComboButtonManager.assignableButtons
        val names      = assignable.map { it.first }.toTypedArray()
        val ids        = assignable.map { it.second }
        val selected   = ComboButtonManager.getButtonsForSlot(slot).toMutableSet()
        val checked    = BooleanArray(names.size) { i -> ids[i] in selected }

        MaterialAlertDialogBuilder(requireContext())
            .setTitle("Assign tombol — Combo $slot (maks ${ComboButtonManager.MAX_BUTTONS_PER_COMBO})")
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
ok "ComboButtonSettingsFragment.kt ditulis ulang."

# =============================================================================
# 4. Tambah string yang kurang di strings.xml
# =============================================================================
echo ">>> Patching strings.xml..."
STRINGS_XML="$RES/values/strings.xml"

python3 - "$STRINGS_XML" << 'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()

to_add = {}
if 'combo_button_none_assigned' not in src:
    to_add['combo_button_none_assigned'] = '(tidak ada)'
if 'combo_clear_all' not in src:
    to_add['combo_clear_all'] = 'Hapus semua'
if 'combo_button_max_exceeded' not in src:
    to_add['combo_button_max_exceeded'] = 'Maks %d tombol per combo'
if 'combo_button_settings' not in src:
    to_add['combo_button_settings'] = 'Combo Buttons'
if 'combo_button_settings_description' not in src:
    to_add['combo_button_settings_description'] = 'Konfigurasi pintasan multi-tombol untuk overlay'

if not to_add:
    print("  strings already present")
else:
    lines = '\n'.join(f'    <string name="{k}">{v}</string>' for k, v in to_add.items())
    src = src.replace('</resources>', f'\n    <!-- Combo Buttons -->\n{lines}\n</resources>', 1)
    path.write_text(src)
    print(f"  added: {list(to_add.keys())}")
PYEOF
ok "strings.xml diupdate."

# =============================================================================
# Done
# =============================================================================
echo ""
echo "============================================="
echo -e "${GREEN}  Fix UI selesai!${NC}"
echo "============================================="
echo ""
echo "Jalankan:"
echo "  git add -A && git commit -m \"fix(ui): rewrite ComboButtonSettingsFragment with Material Design\" && git push"
echo ""
