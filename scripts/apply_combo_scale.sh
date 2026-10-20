#!/usr/bin/env bash
# =============================================================================
# apply_combo_scale.sh
#
# Tambah pengaturan scale per Combo Button 1-5 di ComboButtonSettingsFragment,
# konsisten dengan cara button lain mengatur scale via controlScale-$buttonId.
#
# Jalankan dari ROOT repo:
#   bash scripts/apply_combo_scale.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

BASE=""
for candidate in "src/android" "app" "."; do
    if [[ -f "$candidate/app/src/main/java/org/citra/citra_emu/fragments/HomeSettingsFragment.kt" ]]; then
        BASE="$candidate"; break
    fi
done
[[ -n "$BASE" ]] || die "Tidak menemukan repo root."
ok "Base path: $BASE"

APP="$BASE/app/src/main/java/org/citra/citra_emu"
RES="$BASE/app/src/main/res"
COMBO_FRAG="$APP/features/settings/ui/ComboButtonSettingsFragment.kt"
ITEM_LAYOUT="$RES/layout/item_combo_button.xml"
STRINGS_XML="$RES/values/strings.xml"

[[ -f "$COMBO_FRAG" ]]   || die "Tidak menemukan ComboButtonSettingsFragment.kt"
[[ -f "$ITEM_LAYOUT" ]]  || die "Tidak menemukan item_combo_button.xml"

already_patched() { grep -q "$1" "$2" 2>/dev/null; }

echo ""
echo "============================================="
echo "  Combo Button Scale Patch                   "
echo "============================================="
echo ""

# =============================================================================
# 1. item_combo_button.xml — tambah SeekBar scale setelah btn_edit
# =============================================================================
echo ">>> Patching item_combo_button.xml..."

if already_patched "combo_scale_label" "$ITEM_LAYOUT"; then
    warn "item_combo_button.xml already patched — skipping."
else
python3 - "$ITEM_LAYOUT" << 'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()

OLD = '''\
        <!-- Edit button -->
        <com.google.android.material.button.MaterialButton
            android:id="@+id/btn_edit"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Select Buttons..."
            style="@style/Widget.MaterialComponents.Button.OutlinedButton" />'''

NEW = '''\
        <!-- Edit button -->
        <com.google.android.material.button.MaterialButton
            android:id="@+id/btn_edit"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Select Buttons..."
            style="@style/Widget.MaterialComponents.Button.OutlinedButton" />

        <!-- Scale control -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:layout_marginTop="8dp">

            <TextView
                android:id="@+id/combo_scale_label"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="Size:"
                android:textAppearance="?attr/textAppearanceLabelMedium"
                android:layout_marginEnd="8dp" />

            <SeekBar
                android:id="@+id/combo_scale_seekbar"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_weight="1"
                android:max="100"
                android:progress="50" />

            <TextView
                android:id="@+id/combo_scale_value"
                android:layout_width="32dp"
                android:layout_height="wrap_content"
                android:gravity="end"
                android:textAppearance="?attr/textAppearanceLabelMedium"
                android:layout_marginStart="8dp"
                android:text="50" />

        </LinearLayout>'''

assert OLD in src, "Anchor (btn_edit) not found"
path.write_text(src.replace(OLD, NEW, 1))
print("  written")
PYEOF
    ok "item_combo_button.xml patched."
fi

# =============================================================================
# 2. ComboButtonSettingsFragment.kt — tambah logika scale SeekBar
# =============================================================================
echo ">>> Patching ComboButtonSettingsFragment.kt..."

if already_patched "combo_scale_seekbar" "$COMBO_FRAG"; then
    warn "ComboButtonSettingsFragment.kt already patched — skipping."
else
python3 - "$COMBO_FRAG" << 'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()

# ── 2a. Tambah import SeekBar listener ──────────────────────────────────────
OLD_IMPORT = "import androidx.fragment.app.Fragment"
NEW_IMPORT  = """import android.widget.SeekBar
import androidx.fragment.app.Fragment"""

if OLD_IMPORT in src and "android.widget.SeekBar" not in src:
    src = src.replace(OLD_IMPORT, NEW_IMPORT, 1)

# ── 2b. Tambah fungsi getScaleKey helper di companion / top-level ────────────
# Sisipkan sebelum closing class brace
OLD_CLASS_END = """\
    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}"""

NEW_CLASS_END = """\
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
}"""

assert OLD_CLASS_END in src, "Anchor (onDestroyView) not found"
src = src.replace(OLD_CLASS_END, NEW_CLASS_END, 1)

# ── 2c. Tambah bindScale di akhir fungsi bindSlot ────────────────────────────
OLD_BIND_END = """\
        card.btnEdit.setOnClickListener {
            showPickerDialog(slot) { refreshChips() }
        }
    }"""

NEW_BIND_END = """\
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
    }"""

assert OLD_BIND_END in src, "Anchor (bindSlot end) not found"
src = src.replace(OLD_BIND_END, NEW_BIND_END, 1)

path.write_text(src)
print("  written")
PYEOF
    ok "ComboButtonSettingsFragment.kt patched."
fi

# =============================================================================
# 3. strings.xml — tambah string scale jika belum ada
# =============================================================================
echo ">>> Patching strings.xml..."

if already_patched "combo_scale_size" "$STRINGS_XML"; then
    warn "strings.xml scale string already present — skipping."
else
python3 - "$STRINGS_XML" << 'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()
OLD = '    <!-- Combo Buttons -->'
NEW = '    <!-- Combo Buttons -->\n    <string name="combo_scale_size">Size</string>'
if OLD in src:
    path.write_text(src.replace(OLD, NEW, 1))
    print("  added combo_scale_size string")
else:
    # Fallback ke </resources>
    path.write_text(src.replace(
        '</resources>',
        '    <string name="combo_scale_size">Size</string>\n</resources>',
        1
    ))
    print("  added via fallback")
PYEOF
    ok "strings.xml patched."
fi

# =============================================================================
# Done
# =============================================================================
echo ""
echo "============================================="
echo -e "${GREEN}  Scale patch selesai!${NC}"
echo "============================================="
echo ""
echo "Jalankan:"
echo "  git add -A && git commit -m \"feat(ui): add per-combo button scale control in settings\" && git push"
echo ""
