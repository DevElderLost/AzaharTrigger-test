#!/usr/bin/env bash
# =============================================================================
# apply_combo_ui.sh
#
# Patch #2 — Wires Combo Button Settings into the UI:
#   1. HomeSettingsFragment.kt  → tambah entry "Combo Buttons" di optionsList
#   2. EmulationFragment.kt     → tambah 5 checkbox Combo di showToggleControlsDialog
#                                  dan resetInputOverlay
#   3. res/values/arrays.xml    → tambah 5 item "Combo N" ke array n3dsButtons
#   4. res/navigation/home_navigation.xml → tambah fragment + action combo
#
# Jalankan dari ROOT repo:
#   bash scripts/apply_combo_ui.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

# ── Auto-detect base path ────────────────────────────────────────────────────
BASE=""
for candidate in "src/android" "app" "."; do
    if [[ -f "$candidate/app/src/main/java/org/citra/citra_emu/fragments/HomeSettingsFragment.kt" ]]; then
        BASE="$candidate"
        break
    fi
done
[[ -n "$BASE" ]] || die "Cannot locate HomeSettingsFragment.kt — run from repo root."
ok "Detected base path: $BASE"

APP="$BASE/app/src/main/java/org/citra/citra_emu"
RES="$BASE/app/src/main/res"

HOME_FRAG="$APP/fragments/HomeSettingsFragment.kt"
EMUL_FRAG="$APP/fragments/EmulationFragment.kt"
ARRAYS_XML="$RES/values/arrays.xml"
NAV_XML="$RES/navigation/home_navigation.xml"

[[ -f "$HOME_FRAG" ]]  || die "Not found: $HOME_FRAG"
[[ -f "$EMUL_FRAG" ]]  || die "Not found: $EMUL_FRAG"
[[ -f "$ARRAYS_XML" ]] || die "Not found: $ARRAYS_XML"
[[ -f "$NAV_XML" ]]    || die "Not found: $NAV_XML"

already_patched() { grep -q "$1" "$2" 2>/dev/null; }

echo ""
echo "============================================="
echo "  AzaharTrigger — Combo UI Patcher (Patch 2)"
echo "============================================="
echo ""

# =============================================================================
# 1. HomeSettingsFragment.kt — tambah entry "Combo Buttons"
# =============================================================================
echo ">>> Patching HomeSettingsFragment.kt ..."

if already_patched "action_homeSettingsFragment_to_comboButtonSettingsFragment" "$HOME_FRAG"; then
    warn "HomeSettingsFragment.kt already patched — skipping."
else
python3 - "$HOME_FRAG" <<'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()

# Sisipkan SEBELUM entry "about" (entry terakhir di optionsList)
OLD = """\
            HomeSetting(
                R.string.about,
                R.string.about_description,
                R.drawable.ic_info_outline,
                {
                    exitTransition = MaterialSharedAxis(MaterialSharedAxis.X, true)
                    parentFragmentManager.primaryNavigationFragment?.findNavController()
                        ?.navigate(R.id.action_homeSettingsFragment_to_aboutFragment)
                }
            )"""

NEW = """\
            HomeSetting(
                R.string.combo_button_settings,
                R.string.combo_button_settings_description,
                R.drawable.ic_controller,
                {
                    exitTransition = MaterialSharedAxis(MaterialSharedAxis.X, true)
                    parentFragmentManager.primaryNavigationFragment?.findNavController()
                        ?.navigate(R.id.action_homeSettingsFragment_to_comboButtonSettingsFragment)
                }
            ),
            HomeSetting(
                R.string.about,
                R.string.about_description,
                R.drawable.ic_info_outline,
                {
                    exitTransition = MaterialSharedAxis(MaterialSharedAxis.X, true)
                    parentFragmentManager.primaryNavigationFragment?.findNavController()
                        ?.navigate(R.id.action_homeSettingsFragment_to_aboutFragment)
                }
            )"""

assert OLD in src, "Anchor (about HomeSetting block) not found"
path.write_text(src.replace(OLD, NEW, 1))
print("  written")
PYEOF
    ok "HomeSettingsFragment.kt patched."
fi

# =============================================================================
# 2. EmulationFragment.kt — patch showToggleControlsDialog (16→21 buttons)
# =============================================================================
echo ">>> Patching EmulationFragment.kt — showToggleControlsDialog ..."

if already_patched "BooleanArray(21)" "$EMUL_FRAG"; then
    warn "EmulationFragment.kt toggleDialog already patched — skipping."
else
python3 - "$EMUL_FRAG" <<'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()

OLD = """\
    private fun showToggleControlsDialog() {
        val editor = preferences.edit()
        val enabledButtons = BooleanArray(16)
        enabledButtons.forEachIndexed { i: Int, _: Boolean ->
            // Buttons that are disabled by default
            var defaultValue = true
            when (i) {
                // TODO: Remove these magic numbers
                6, 7, 12, 13, 14, 15 -> defaultValue = false
            }
            enabledButtons[i] = preferences.getBoolean(\"buttonToggle$i\", defaultValue)
        }

        val dialog = MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.emulation_toggle_controls)
            .setMultiChoiceItems(
                R.array.n3dsButtons, enabledButtons
            ) { _: DialogInterface?, indexSelected: Int, isChecked: Boolean ->
                editor.putBoolean(\"buttonToggle$indexSelected\", isChecked)
            }
            .setPositiveButton(android.R.string.ok) { _: DialogInterface?, _: Int ->
                editor.apply()
                binding.surfaceInputOverlay.refreshControls()
            }
            .show()"""

NEW = """\
    private fun showToggleControlsDialog() {
        val editor = preferences.edit()
        // Indices 0-15  = tombol standar 3DS
        // Indices 16-20 = Combo Button 1-5
        val enabledButtons = BooleanArray(21)
        enabledButtons.forEachIndexed { i: Int, _: Boolean ->
            var defaultValue = true
            when (i) {
                // Disabled by default: turbo, swap, home, extra, combo buttons
                6, 7, 12, 13, 14, 15, 16, 17, 18, 19, 20 -> defaultValue = false
            }
            enabledButtons[i] = preferences.getBoolean(\"buttonToggle$i\", defaultValue)
        }

        val dialog = MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.emulation_toggle_controls)
            .setMultiChoiceItems(
                R.array.n3dsButtons, enabledButtons
            ) { _: DialogInterface?, indexSelected: Int, isChecked: Boolean ->
                editor.putBoolean(\"buttonToggle$indexSelected\", isChecked)
                // Sync combo enabled state ke ComboButtonManager
                if (indexSelected in 16..20) {
                    val slot = indexSelected - 15  // 16->1, 17->2, ...
                    org.citra.citra_emu.overlay.ComboButtonManager.setEnabled(slot, isChecked)
                }
            }
            .setPositiveButton(android.R.string.ok) { _: DialogInterface?, _: Int ->
                editor.apply()
                binding.surfaceInputOverlay.refreshControls()
            }
            .show()"""

assert OLD in src, "Anchor (showToggleControlsDialog) not found"
path.write_text(src.replace(OLD, NEW, 1))
print("  written")
PYEOF
    ok "EmulationFragment.kt — toggleDialog patched."
fi

# =============================================================================
# 3. EmulationFragment.kt — patch resetInputOverlay (loop 16→21)
# =============================================================================
echo ">>> Patching EmulationFragment.kt — resetInputOverlay ..."

if already_patched "0 until 21" "$EMUL_FRAG"; then
    warn "EmulationFragment.kt resetInputOverlay already patched — skipping."
else
python3 - "$EMUL_FRAG" <<'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()

OLD = """\
        val editor = preferences.edit()
        for (i in 0 until 16) {
            var defaultValue = true
            when (i) {
                6, 7, 12, 13, 14, 15 -> defaultValue = false
            }
            editor.putBoolean(\"buttonToggle$i\", defaultValue)
        }
        editor.apply()"""

NEW = """\
        val editor = preferences.edit()
        for (i in 0 until 21) {
            var defaultValue = true
            when (i) {
                6, 7, 12, 13, 14, 15, 16, 17, 18, 19, 20 -> defaultValue = false
            }
            editor.putBoolean(\"buttonToggle$i\", defaultValue)
        }
        editor.apply()
        // Reset combo button enabled states
        for (slot in 1..5) {
            org.citra.citra_emu.overlay.ComboButtonManager.setEnabled(slot, false)
        }"""

assert OLD in src, "Anchor (resetInputOverlay for loop) not found"
path.write_text(src.replace(OLD, NEW, 1))
print("  written")
PYEOF
    ok "EmulationFragment.kt — resetInputOverlay patched."
fi

# =============================================================================
# 4. res/values/arrays.xml — append Combo 1-5 ke array n3dsButtons
# =============================================================================
echo ">>> Patching res/values/arrays.xml ..."

if already_patched "Combo 1" "$ARRAYS_XML"; then
    warn "arrays.xml already patched — skipping."
else
python3 - "$ARRAYS_XML" <<'PYEOF'
import sys, pathlib, re
path = pathlib.Path(sys.argv[1])
src  = path.read_text()

# Cari closing tag array n3dsButtons dan sisipkan 5 item baru sebelumnya
# Pattern: cari </string-array> yang menutup array n3dsButtons
# Strategi: temukan blok <string-array name="n3dsButtons"> ... </string-array>
pattern = r'(<string-array name="n3dsButtons">.*?)(</string-array>)'
match = re.search(pattern, src, re.DOTALL)
assert match, 'Array n3dsButtons not found in arrays.xml'

combo_items = """        <item>Combo 1</item>
        <item>Combo 2</item>
        <item>Combo 3</item>
        <item>Combo 4</item>
        <item>Combo 5</item>
"""
new_block = match.group(1) + combo_items + match.group(2)
path.write_text(src[:match.start()] + new_block + src[match.end():])
print("  written")
PYEOF
    ok "arrays.xml patched."
fi

# =============================================================================
# 5. res/navigation/home_navigation.xml — tambah fragment + action combo
# =============================================================================
echo ">>> Patching nav_home.xml ..."

if already_patched "comboButtonSettingsFragment" "$NAV_XML"; then
    warn "nav_home.xml already patched — skipping."
else
python3 - "$NAV_XML" <<'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()

# 5a. Tambah action ke dalam fragment homeSettingsFragment
OLD_ACTION = '        <action\n            android:id="@+id/action_homeSettingsFragment_to_aboutFragment"'
NEW_ACTION  = '''\
        <action
            android:id="@+id/action_homeSettingsFragment_to_comboButtonSettingsFragment"
            app:destination="@id/comboButtonSettingsFragment" />
        <action
            android:id="@+id/action_homeSettingsFragment_to_aboutFragment"'''
assert OLD_ACTION in src, "Anchor (action_to_aboutFragment) not found in nav_home.xml"
src = src.replace(OLD_ACTION, NEW_ACTION, 1)

# 5b. Tambah fragment destination sebelum closing </navigation>
OLD_NAV = '</navigation>'
NEW_FRAG = '''\
    <fragment
        android:id="@+id/comboButtonSettingsFragment"
        android:name="org.citra.citra_emu.features.settings.ui.ComboButtonSettingsFragment"
        android:label="Combo Buttons" />

</navigation>'''
assert OLD_NAV in src, "Closing </navigation> tag not found"
src = src.replace(OLD_NAV, NEW_FRAG, 1)

path.write_text(src)
print("  written")
PYEOF
    ok "nav_home.xml patched."
fi

# =============================================================================
# 6. strings.xml — tambah string resources combo (jika belum ada)
# =============================================================================
echo ">>> Patching res/values/strings.xml ..."
STRINGS_XML="$RES/values/strings.xml"

if already_patched "combo_button_settings" "$STRINGS_XML"; then
    warn "strings.xml already patched — skipping."
else
python3 - "$STRINGS_XML" <<'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()

# Sisipkan sebelum </resources>
OLD = '</resources>'
NEW = '''\
    <!-- Combo Buttons -->
    <string name="combo_button_settings">Combo Buttons</string>
    <string name="combo_button_settings_description">Configure multi-button combo shortcuts for the overlay</string>

</resources>'''
assert OLD in src, "Closing </resources> not found in strings.xml"
path.write_text(src.replace(OLD, NEW, 1))
print("  written")
PYEOF
    ok "strings.xml patched."
fi

# =============================================================================
# Done
# =============================================================================
echo ""
echo "============================================="
echo -e "${GREEN}  Patch 2 complete!${NC}"
echo "============================================="
echo ""
echo "Selanjutnya:"
echo "  git add -A && git commit -m \"feat(ui): wire Combo Buttons into HomeSettings and overlay toggle\" && git push"
echo ""
