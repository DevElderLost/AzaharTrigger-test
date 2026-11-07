#!/usr/bin/env bash
# =============================================================================
# apply_combo_scale_menu.sh
#
# Tambah scale control Combo 1-5 ke dalam Overlay Options menu
# (sama seperti button A, B, L, R, dll)
#
# Files yang diubah:
#   1. EmulationFragment.kt  — tambah showAdjustScaleDialog untuk combo 1-5
#   2. EmulationFragment.kt  — tambah resetScale untuk combo 1-5
#   3. res/menu/menu_overlay_options.xml — tambah 5 menu item scale combo
#
# Jalankan dari ROOT repo:
#   bash scripts/apply_combo_scale_menu.sh
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
EMUL_FRAG="$APP/fragments/EmulationFragment.kt"
MENU_XML="$RES/menu/menu_overlay_options.xml"

[[ -f "$EMUL_FRAG" ]] || die "Tidak menemukan EmulationFragment.kt"
[[ -f "$MENU_XML" ]]  || die "Tidak menemukan menu_overlay_options.xml"

already_patched() { grep -q "$1" "$2" 2>/dev/null; }

echo ""
echo "============================================="
echo "  Combo Scale Menu Patch                     "
echo "============================================="
echo ""

# =============================================================================
# 1. EmulationFragment.kt — tambah scale dialog entries untuk combo 1-5
#    Sisipkan setelah entry BUTTON_SWAP (entry scale terakhir yang ada)
# =============================================================================
echo ">>> Patching EmulationFragment.kt — scale dialog entries..."

if already_patched "menu_emulation_adjust_scale_combo_1" "$EMUL_FRAG"; then
    warn "Scale dialog entries already patched — skipping."
else
python3 - "$EMUL_FRAG" << 'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()

OLD = """\
                R.id.menu_emulation_adjust_scale_button_swap -> {
                    showAdjustScaleDialog(\"controlScale-\" + NativeLibrary.ButtonType.BUTTON_SWAP)
                    true
                }

                R.id.menu_emulation_adjust_opacity -> {"""

NEW = """\
                R.id.menu_emulation_adjust_scale_button_swap -> {
                    showAdjustScaleDialog("controlScale-" + NativeLibrary.ButtonType.BUTTON_SWAP)
                    true
                }

                R.id.menu_emulation_adjust_scale_combo_1 -> {
                    showAdjustScaleDialog("controlScale-" + org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_1)
                    true
                }

                R.id.menu_emulation_adjust_scale_combo_2 -> {
                    showAdjustScaleDialog("controlScale-" + org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_2)
                    true
                }

                R.id.menu_emulation_adjust_scale_combo_3 -> {
                    showAdjustScaleDialog("controlScale-" + org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_3)
                    true
                }

                R.id.menu_emulation_adjust_scale_combo_4 -> {
                    showAdjustScaleDialog("controlScale-" + org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_4)
                    true
                }

                R.id.menu_emulation_adjust_scale_combo_5 -> {
                    showAdjustScaleDialog("controlScale-" + org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_5)
                    true
                }

                R.id.menu_emulation_adjust_opacity -> {"""

assert OLD in src, "Anchor (BUTTON_SWAP scale + adjust_opacity) not found"
path.write_text(src.replace(OLD, NEW, 1))
print("  scale dialog entries written")
PYEOF
    ok "EmulationFragment.kt — scale entries patched."
fi

# =============================================================================
# 2. EmulationFragment.kt — tambah resetScale untuk combo 1-5 di resetAllScales()
# =============================================================================
echo ">>> Patching EmulationFragment.kt — resetAllScales()..."

if already_patched "COMBO_BUTTON_1" "$EMUL_FRAG"; then
    warn "resetAllScales already patched — skipping."
else
python3 - "$EMUL_FRAG" << 'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()

OLD = """\
        resetScale(\"controlScale-\" + NativeLibrary.ButtonType.BUTTON_SWAP)
        binding.surfaceInputOverlay.refreshControls()
    }"""

NEW = """\
        resetScale("controlScale-" + NativeLibrary.ButtonType.BUTTON_SWAP)
        resetScale("controlScale-" + org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_1)
        resetScale("controlScale-" + org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_2)
        resetScale("controlScale-" + org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_3)
        resetScale("controlScale-" + org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_4)
        resetScale("controlScale-" + org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_5)
        binding.surfaceInputOverlay.refreshControls()
    }"""

assert OLD in src, "Anchor (BUTTON_SWAP resetScale) not found"
path.write_text(src.replace(OLD, NEW, 1))
print("  resetAllScales written")
PYEOF
    ok "EmulationFragment.kt — resetAllScales patched."
fi

# =============================================================================
# 3. menu_overlay_options.xml — tambah 5 item scale combo
#    Sisipkan setelah item scale button_swap
# =============================================================================
echo ">>> Patching menu_overlay_options.xml..."

if already_patched "adjust_scale_combo_1" "$MENU_XML"; then
    warn "menu_overlay_options.xml already patched — skipping."
else
python3 - "$MENU_XML" << 'PYEOF'
import sys, pathlib, re
path = pathlib.Path(sys.argv[1])
src  = path.read_text()

# Cari item terakhir scale yang ada (button_swap) dan sisipkan setelahnya
# Pattern: item dengan id adjust_scale_button_swap
pattern = r'(<item[^>]+android:id="@\+id/menu_emulation_adjust_scale_button_swap"[^/]*/?>)'
match = re.search(pattern, src)
assert match, "Item adjust_scale_button_swap not found in menu XML"

combo_items = """
        <item
            android:id="@+id/menu_emulation_adjust_scale_combo_1"
            android:title="@string/emulation_combo1_scale" />
        <item
            android:id="@+id/menu_emulation_adjust_scale_combo_2"
            android:title="@string/emulation_combo2_scale" />
        <item
            android:id="@+id/menu_emulation_adjust_scale_combo_3"
            android:title="@string/emulation_combo3_scale" />
        <item
            android:id="@+id/menu_emulation_adjust_scale_combo_4"
            android:title="@string/emulation_combo4_scale" />
        <item
            android:id="@+id/menu_emulation_adjust_scale_combo_5"
            android:title="@string/emulation_combo5_scale" />"""

insert_pos = match.end()
src = src[:insert_pos] + combo_items + src[insert_pos:]
path.write_text(src)
print("  menu XML written")
PYEOF
    ok "menu_overlay_options.xml patched."
fi

# =============================================================================
# 4. strings.xml — tambah string untuk menu items
# =============================================================================
echo ">>> Patching strings.xml..."
STRINGS_XML="$RES/values/strings.xml"

if already_patched "emulation_combo1_scale" "$STRINGS_XML"; then
    warn "strings.xml already patched — skipping."
else
python3 - "$STRINGS_XML" << 'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()

new_strings = """\
    <string name="emulation_combo1_scale">Combo 1 Scale</string>
    <string name="emulation_combo2_scale">Combo 2 Scale</string>
    <string name="emulation_combo3_scale">Combo 3 Scale</string>
    <string name="emulation_combo4_scale">Combo 4 Scale</string>
    <string name="emulation_combo5_scale">Combo 5 Scale</string>
"""

src = src.replace('</resources>', new_strings + '</resources>', 1)
path.write_text(src)
print("  strings written")
PYEOF
    ok "strings.xml patched."
fi

# =============================================================================
# Done
# =============================================================================
echo ""
echo "============================================="
echo -e "${GREEN}  Combo Scale Menu Patch selesai!${NC}"
echo "============================================="
echo ""
echo "Jalankan:"
echo "  git add -A && git commit -m \"feat(overlay): add Combo 1-5 scale controls to overlay options menu\" && git push"
echo ""
