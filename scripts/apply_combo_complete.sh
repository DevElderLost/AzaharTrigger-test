#!/usr/bin/env bash
# =============================================================================
# apply_combo_complete.sh
#
# Script GABUNGAN lengkap untuk fitur Combo Button:
#   1. Drawable SVG unik untuk Combo 1-5 (C1..C5)
#   2. InputOverlay.kt — pakai drawable masing-masing, fix posisi default,
#      fix defaultOverlay(), hapus kondisi ganda
#   3. ComboButtonSettingsFragment.kt — tulis ulang tanpa label name,
#      UI Material Design konsisten
#   4. item_combo_button.xml — layout card tanpa field label
#   5. strings.xml — semua bahasa Inggris
#
# Jalankan dari ROOT repo:
#   bash scripts/apply_combo_complete.sh
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
[[ -n "$BASE" ]] || die "Tidak bisa menemukan repo root."
ok "Base path: $BASE"

APP="$BASE/app/src/main/java/org/citra/citra_emu"
RES="$BASE/app/src/main/res"
DRAWABLE="$RES/drawable"
LAYOUT="$RES/layout"
OVERLAY_KT="$APP/overlay/InputOverlay.kt"
COMBO_FRAG="$APP/features/settings/ui/ComboButtonSettingsFragment.kt"
STRINGS_XML="$RES/values/strings.xml"

[[ -f "$OVERLAY_KT" ]] || die "Tidak menemukan InputOverlay.kt"

mkdir -p "$DRAWABLE" "$LAYOUT"

echo ""
echo "================================================"
echo "  AzaharTrigger — Combo Button Complete Patch   "
echo "================================================"
echo ""

# =============================================================================
# 1. DRAWABLE — Buat 5 pasang SVG icon unik untuk Combo 1-5
#    Style: lingkaran solid dengan teks C1..C5 di tengah
#    Dua versi: default (biru) dan pressed (lebih gelap)
# =============================================================================
echo ">>> Writing combo button drawables..."

for N in 1 2 3 4 5; do
cat > "$DRAWABLE/button_combo_${N}.xml" << XML
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <shape android:shape="oval">
            <solid android:color="#CC1A73E8"/>
            <stroke android:width="2dp" android:color="#FFFFFF"/>
            <size android:width="56dp" android:height="56dp"/>
        </shape>
    </item>
    <item>
        <bitmap
            android:gravity="center"
            android:src="@drawable/button_combo_${N}_text"/>
    </item>
</layer-list>
XML

cat > "$DRAWABLE/button_combo_${N}_pressed.xml" << XML
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <shape android:shape="oval">
            <solid android:color="#EE0D47D1"/>
            <stroke android:width="2dp" android:color="#AAAAAA"/>
            <size android:width="56dp" android:height="56dp"/>
        </shape>
    </item>
    <item>
        <bitmap
            android:gravity="center"
            android:src="@drawable/button_combo_${N}_text"/>
    </item>
</layer-list>
XML
done

# Text label drawable (vector) untuk tiap combo — teks "C1".."C5"
for N in 1 2 3 4 5; do
cat > "$DRAWABLE/button_combo_${N}_text.xml" << XML
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="56dp"
    android:height="56dp"
    android:viewportWidth="56"
    android:viewportHeight="56">
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M14,34 L14,22 L17,22 L17,28.5 L20.5,22 L24,22 L20,28 L24.5,34 L20.8,34 L17,27.5 L17,34 Z"/>
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M32,34 C28.7,34 27,32.2 27,28 C27,23.8 28.7,22 32,22 C33.5,22 34.7,22.5 35.5,23.4 L33.8,25.1 C33.3,24.5 32.7,24.2 32,24.2 C30.5,24.2 29.8,25.4 29.8,28 C29.8,30.6 30.5,31.8 32,31.8 C32.8,31.8 33.4,31.4 33.9,30.8 L35.6,32.5 C34.7,33.5 33.5,34 32,34 Z"/>
</vector>
XML
done

# Override text untuk C2..C5 dengan angka yang benar
python3 << 'PYEOF'
import pathlib, os

base = None
for c in ["src/android", "app", "."]:
    if pathlib.Path(f"{c}/app/src/main/res/drawable").exists():
        base = c; break

drawable = pathlib.Path(f"{base}/app/src/main/res/drawable")

# Template SVG path data untuk angka 1-5 di sisi kanan (posisi ~28-38 x)
digits = {
    "1": "M30,22 L33,22 L33,34 L30,34 L30,26 L28,27.5 L28,24.5 Z",
    "2": "M27,22 L36,22 L36,24.5 L30,24.5 L30,27 C33.5,27 36,28.5 36,31 C36,33 34.2,34 31.5,34 C29.5,34 27.8,33.3 27,32.2 L28.8,30.5 C29.3,31.2 30.3,31.8 31.5,31.8 C32.7,31.8 33.2,31.3 33.2,30.5 C33.2,29.5 32.2,29 30,29 L28,29 Z",
    "3": "M27,22 L36,22 L36,24.5 L29.5,24.5 L29.5,27 L33,27 C35,27 36.5,28.2 36.5,30.5 C36.5,32.8 34.8,34 32,34 C30,34 28.3,33.3 27.2,32 L29,30.3 C29.7,31.1 30.7,31.8 32,31.8 C33.2,31.8 33.7,31.2 33.7,30.5 C33.7,29.8 33.2,29.2 32,29.2 L27,29.2 Z",
    "4": "M27,22 L30,22 L30,28 L35,22 L38,22 L33,28.5 L38.5,34 L35,34 L30,28 L30,34 L27,34 Z",
    "5": "M27,22 L36,22 L36,24.5 L30,24.5 L29.5,27.5 C30,27.2 30.8,27 31.5,27 C34,27 36,28.5 36,31.2 C36,33.2 34.3,34 31.5,34 C29.5,34 28,33.3 27,32 L28.8,30.3 C29.4,31.1 30.4,31.8 31.5,31.8 C32.8,31.8 33.2,31.1 33.2,30.3 C33.2,29.5 32.5,29 31.2,29 C30.5,29 29.8,29.2 29.3,29.6 L27,28.5 Z",
}

# Path untuk huruf C (sama untuk semua)
c_path = "M21,34 C17.7,34 16,32.2 16,28 C16,23.8 17.7,22 21,22 C22.5,22 23.7,22.5 24.5,23.4 L22.8,25.1 C22.3,24.5 21.7,24.2 21,24.2 C19.5,24.2 18.8,25.4 18.8,28 C18.8,30.6 19.5,31.8 21,31.8 C21.8,31.8 22.4,31.4 22.9,30.8 L24.6,32.5 C23.7,33.5 22.5,34 21,34 Z"

for n in range(1, 6):
    d_path = digits[str(n)]
    xml = f'''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="56dp"
    android:height="56dp"
    android:viewportWidth="56"
    android:viewportHeight="56">
    <path
        android:fillColor="#FFFFFF"
        android:pathData="{c_path}"/>
    <path
        android:fillColor="#FFFFFF"
        android:pathData="{d_path}"/>
</vector>'''
    out = drawable / f"button_combo_{n}_text.xml"
    out.write_text(xml)
    print(f"  button_combo_{n}_text.xml written")
PYEOF
ok "Combo drawables (C1-C5) dibuat."

# =============================================================================
# 2. InputOverlay.kt — ganti drawable turbo ke per-combo + fix semua logika
# =============================================================================
echo ">>> Patching InputOverlay.kt..."

python3 - "$OVERLAY_KT" << 'PYEOF'
import sys, pathlib, re
path = pathlib.Path(sys.argv[1])
src  = path.read_text()

# ── 2a. Ganti loop combo: hapus inline default posisi, pakai drawable per-slot
OLD = '''\
        // ── Combo Buttons 1–5 (buttonToggle20–24) ────────────────────────
        val comboIds = intArrayOf(
            ComboButtonManager.COMBO_BUTTON_1,
            ComboButtonManager.COMBO_BUTTON_2,
            ComboButtonManager.COMBO_BUTTON_3,
            ComboButtonManager.COMBO_BUTTON_4,
            ComboButtonManager.COMBO_BUTTON_5,
        )
        for (i in comboIds.indices) {
            val slot = i + 1
            val toggleKey = "buttonToggle${20 + i}"
            if (preferences.getBoolean(toggleKey, false)) {
                // Set posisi default jika belum ada di prefs
                val xKey = "${comboIds[i]}-X"
                val yKey = "${comboIds[i]}-Y"
                if (!preferences.contains(xKey)) {
                    val dm = resources.displayMetrics
                    val defaultXRatios = floatArrayOf(0.07f, 0.14f, 0.21f, 0.07f, 0.14f)
                    val defaultYRatios = floatArrayOf(0.75f, 0.75f, 0.75f, 0.88f, 0.88f)
                    preferences.edit()
                        .putFloat(xKey, defaultXRatios[i] * dm.widthPixels)
                        .putFloat(yKey, defaultYRatios[i] * dm.heightPixels)
                        .apply()
                }
                overlayButtons.add(
                    initializeOverlayButton(
                        context,
                        R.drawable.button_turbo,
                        R.drawable.button_turbo_pressed,
                        comboIds[i],
                        orientation
                    )
                )
            }
        }
    }'''

NEW = '''\
        // ── Combo Buttons 1–5 (buttonToggle20–24) ────────────────────────
        val comboIds = intArrayOf(
            ComboButtonManager.COMBO_BUTTON_1,
            ComboButtonManager.COMBO_BUTTON_2,
            ComboButtonManager.COMBO_BUTTON_3,
            ComboButtonManager.COMBO_BUTTON_4,
            ComboButtonManager.COMBO_BUTTON_5,
        )
        val comboDefaultDrawables = intArrayOf(
            R.drawable.button_combo_1,
            R.drawable.button_combo_2,
            R.drawable.button_combo_3,
            R.drawable.button_combo_4,
            R.drawable.button_combo_5,
        )
        val comboPressedDrawables = intArrayOf(
            R.drawable.button_combo_1_pressed,
            R.drawable.button_combo_2_pressed,
            R.drawable.button_combo_3_pressed,
            R.drawable.button_combo_4_pressed,
            R.drawable.button_combo_5_pressed,
        )
        for (i in comboIds.indices) {
            val toggleKey = "buttonToggle${20 + i}"
            if (preferences.getBoolean(toggleKey, false)) {
                overlayButtons.add(
                    initializeOverlayButton(
                        context,
                        comboDefaultDrawables[i],
                        comboPressedDrawables[i],
                        comboIds[i],
                        orientation
                    )
                )
            }
        }
    }'''

assert OLD in src, "Anchor combo loop not found"
src = src.replace(OLD, NEW, 1)

# ── 2b. Fix defaultOverlay() — tambah cek posisi combo
OLD2 = '''\
    private fun defaultOverlay() {
        if (!preferences.getBoolean("OverlayInit", false)) {
            // It\'s possible that a user has created their overlay before this was added
            // Only change the overlay if the \'A\' button is not in the upper corner.
            val aButtonPosition = preferences.getFloat(
                NativeLibrary.ButtonType.BUTTON_A.toString() + "-X",
                0f
            )
            if (aButtonPosition == 0f) {
                defaultOverlayLandscape()
            }

            val aButtonPositionPortrait = preferences.getFloat(
                NativeLibrary.ButtonType.BUTTON_A.toString() + "-Portrait" + "-X",
                0f
            )
            if (aButtonPositionPortrait == 0f) {
                defaultOverlayPortrait()
            }
        }

        preferences.edit()
            .putBoolean("OverlayInit", true)
            .apply()
    }'''

NEW2 = '''\
    private fun defaultOverlay() {
        if (!preferences.getBoolean("OverlayInit", false)) {
            // It\'s possible that a user has created their overlay before this was added
            // Only change the overlay if the \'A\' button is not in the upper corner.
            val aButtonPosition = preferences.getFloat(
                NativeLibrary.ButtonType.BUTTON_A.toString() + "-X",
                0f
            )
            if (aButtonPosition == 0f) {
                defaultOverlayLandscape()
            }

            val aButtonPositionPortrait = preferences.getFloat(
                NativeLibrary.ButtonType.BUTTON_A.toString() + "-Portrait" + "-X",
                0f
            )
            if (aButtonPositionPortrait == 0f) {
                defaultOverlayPortrait()
            }
        }

        // Set posisi default combo button jika belum pernah di-set
        // (user yang install sebelum fitur combo ditambahkan tidak punya key ini)
        val combo1X = preferences.getFloat(
            "${ComboButtonManager.COMBO_BUTTON_1}-X", -1f
        )
        if (combo1X == -1f) {
            defaultOverlayLandscape()
        }
        val combo1PortraitX = preferences.getFloat(
            "${ComboButtonManager.COMBO_BUTTON_1}-Portrait-X", -1f
        )
        if (combo1PortraitX == -1f) {
            defaultOverlayPortrait()
        }

        preferences.edit()
            .putBoolean("OverlayInit", true)
            .apply()
    }'''

if OLD2 in src:
    src = src.replace(OLD2, NEW2, 1)
    print("  defaultOverlay() patched")
else:
    print("  WARN: defaultOverlay anchor not found — skipping")

path.write_text(src)
print("  InputOverlay.kt written")
PYEOF
ok "InputOverlay.kt patched."

# =============================================================================
# 3. Layout XML: item_combo_button.xml — TANPA field label
# =============================================================================
echo ">>> Writing item_combo_button.xml (without label field)..."

cat > "$LAYOUT/item_combo_button.xml" << 'XML'
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

        <!-- Header: icon + judul slot -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:paddingBottom="12dp">

            <ImageView
                android:id="@+id/combo_icon"
                android:layout_width="40dp"
                android:layout_height="40dp"
                android:layout_marginEnd="12dp"
                android:scaleType="fitCenter" />

            <TextView
                android:id="@+id/combo_title"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_weight="1"
                android:textAppearance="?attr/textAppearanceTitleMedium"
                android:textStyle="bold" />

        </LinearLayout>

        <!-- Assigned buttons label -->
        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Assigned buttons (max 4):"
            android:textAppearance="?attr/textAppearanceLabelMedium"
            android:paddingBottom="6dp" />

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
            android:text="Select Buttons..."
            style="@style/Widget.MaterialComponents.Button.OutlinedButton" />

    </LinearLayout>

</com.google.android.material.card.MaterialCardView>
XML
ok "item_combo_button.xml updated (no label field)."

# =============================================================================
# 4. ComboButtonSettingsFragment.kt — tulis ulang tanpa logika label
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
import android.widget.Toast
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
 * Fragment untuk mengatur Combo Buttons 1–5.
 * Setiap slot menampilkan icon combo-nya sendiri dan chip assignment tombol.
 * Toggle show/hide dilakukan via "Toggle Controls" di Overlay Options.
 */
class ComboButtonSettingsFragment : Fragment() {

    private var _binding: FragmentComboButtonSettingsBinding? = null
    private val binding get() = _binding!!

    // Drawable icon per slot
    private val comboIcons = intArrayOf(
        R.drawable.button_combo_1,
        R.drawable.button_combo_2,
        R.drawable.button_combo_3,
        R.drawable.button_combo_4,
        R.drawable.button_combo_5,
    )

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

        binding.toolbar.apply {
            title = getString(R.string.combo_button_settings)
            setNavigationIcon(R.drawable.ic_back)
            setNavigationOnClickListener { findNavController().popBackStack() }
        }

        for (slot in 1..ComboButtonManager.COMBO_COUNT) {
            val cardBinding = ItemComboButtonBinding.inflate(
                layoutInflater, binding.comboContainer, true
            )
            bindSlot(cardBinding, slot)
        }
    }

    private fun bindSlot(card: ItemComboButtonBinding, slot: Int) {
        // Icon per slot
        card.comboIcon.setImageResource(comboIcons[slot - 1])

        // Judul
        card.comboTitle.text = "Combo $slot"

        // Chips assignment
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

# =============================================================================
# 5. strings.xml — pastikan semua string combo ada dan dalam bahasa Inggris
# =============================================================================
echo ">>> Updating strings.xml..."

python3 - "$STRINGS_XML" << 'PYEOF'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
src  = path.read_text()

# Hapus semua string combo lama yang mungkin ada (bahasa Indonesia atau duplikat)
src = re.sub(r'\s*<!--\s*Combo Buttons\s*-->\s*\n', '\n', src)
for key in ['combo_button_settings', 'combo_button_settings_description',
            'combo_button_none_assigned', 'combo_clear_all',
            'combo_button_max_exceeded']:
    src = re.sub(rf'\s*<string name="{key}">[^<]*</string>\n', '\n', src)

# Hapus baris kosong berlebih
src = re.sub(r'\n{3,}', '\n\n', src)

# Sisipkan semua string combo sebelum </resources>
new_strings = '''
    <!-- Combo Buttons -->
    <string name="combo_button_settings">Combo Buttons</string>
    <string name="combo_button_settings_description">Configure multi-button combo shortcuts for the overlay</string>
    <string name="combo_button_none_assigned">(none assigned)</string>
    <string name="combo_clear_all">Clear all</string>
    <string name="combo_button_max_exceeded">Max %d buttons per combo</string>
'''

src = src.replace('</resources>', new_strings + '</resources>', 1)
path.write_text(src)
print("  strings.xml updated")
PYEOF
ok "strings.xml updated."

# =============================================================================
# 6. fragment_combo_button_settings.xml — pastikan paddingBottom ada
# =============================================================================
FRAG_LAYOUT="$LAYOUT/fragment_combo_button_settings.xml"
if [[ -f "$FRAG_LAYOUT" ]]; then
    python3 - "$FRAG_LAYOUT" << 'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()
if 'paddingBottom' not in src:
    src = src.replace(
        'android:layout_height="match_parent">',
        'android:layout_height="match_parent"\n        android:clipToPadding="false"\n        android:paddingBottom="80dp">',
        1
    )
    path.write_text(src)
    print("  paddingBottom added")
else:
    print("  already has paddingBottom")
PYEOF
fi
ok "fragment_combo_button_settings.xml checked."

# =============================================================================
# Done
# =============================================================================
echo ""
echo "================================================"
echo -e "${GREEN}  Complete patch selesai!${NC}"
echo "================================================"
echo ""
echo "Jalankan:"
echo "  git add -A && git commit -m \"feat(overlay): complete combo button with unique icons and clean settings UI\" && git push"
echo ""
