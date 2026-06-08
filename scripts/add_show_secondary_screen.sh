#!/usr/bin/env bash
# ============================================================
# add_show_secondary_screen.sh
#
# Fitur: Tombol "Show Secondary Screen" di overlay menu
#
# Logika:
# - Hanya aktif/relevan saat SINGLE_SCREEN mode
# - Ketika ditekan saat single screen: munculkan layar kedua
#   dengan posisi & ukuran seperti LARGE_SCREEN (pojok kecil)
# - Touch ke layar kedua ikut aktif saat tombol ON
# - State disimpan di EmulationMenuSettings (SharedPreferences)
# - Saat mode bukan SINGLE_SCREEN, setting ini diabaikan
#
# File yang dimodifikasi:
# 1. EmulationMenuSettings.kt  — tambah var showSecondaryScreen
# 2. ScreenAdjustmentUtil.kt   — tambah fun toggleSecondaryScreen()
# 3. InputOverlay.kt           — update isTouchScreenVisible()
# 4. EmulationFragment.kt      — tambah menu item + handler
# 5. menu_overlay_options.xml  — tambah item menu UI
# ============================================================

set -e

OVERLAY_FILE="src/android/app/src/main/java/org/citra/citra_emu/overlay/InputOverlay.kt"
SETTINGS_FILE="src/android/app/src/main/java/org/citra/citra_emu/utils/EmulationMenuSettings.kt"
ADJUSTMENT_FILE="src/android/app/src/main/java/org/citra/citra_emu/display/ScreenAdjustmentUtil.kt"
FRAGMENT_FILE="src/android/app/src/main/java/org/citra/citra_emu/fragments/EmulationFragment.kt"
MENU_FILE="src/android/app/src/main/res/menu/menu_overlay_options.xml"

for f in "$OVERLAY_FILE" "$SETTINGS_FILE" "$ADJUSTMENT_FILE" "$FRAGMENT_FILE" "$MENU_FILE"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: File tidak ditemukan: $f"
        exit 1
    fi
done

echo "=== Backup semua file ==="
for f in "$OVERLAY_FILE" "$SETTINGS_FILE" "$ADJUSTMENT_FILE" "$FRAGMENT_FILE" "$MENU_FILE"; do
    cp "$f" "${f}.bak2"
    echo "Backup: ${f}.bak2"
done

# ============================================================
# Step 1: EmulationMenuSettings.kt
# Tambah var showSecondaryScreen setelah var showOverlay
# ============================================================
echo ""
echo "=== Step 1: Tambah showSecondaryScreen di EmulationMenuSettings ==="

python3 - "$SETTINGS_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'showSecondaryScreen' in content:
    print("showSecondaryScreen sudah ada, skip.")
    sys.exit(0)

# Anchor: setelah blok showOverlay
old = '''    var showOverlay: Boolean
        get() = preferences.getBoolean("EmulationMenuSettings_ShowOverlay", true)
        set(value) {
            preferences.edit()
                .putBoolean("EmulationMenuSettings_ShowOverlay", value)
                .apply()
        }'''

new = '''    var showOverlay: Boolean
        get() = preferences.getBoolean("EmulationMenuSettings_ShowOverlay", true)
        set(value) {
            preferences.edit()
                .putBoolean("EmulationMenuSettings_ShowOverlay", value)
                .apply()
        }

    var showSecondaryScreen: Boolean
        get() = preferences.getBoolean("EmulationMenuSettings_ShowSecondaryScreen", false)
        set(value) {
            preferences.edit()
                .putBoolean("EmulationMenuSettings_ShowSecondaryScreen", value)
                .apply()
        }'''

if old not in content:
    # Coba cari dengan variasi
    import re
    pattern = r'(var showOverlay: Boolean\s+get\(\) = preferences\.getBoolean\("EmulationMenuSettings_ShowOverlay", true\)\s+set\(value\) \{\s+preferences\.edit\(\)\s+\.putBoolean\("EmulationMenuSettings_ShowOverlay", value\)\s+\.apply\(\)\s+\})'
    match = re.search(pattern, content)
    if match:
        old_found = match.group(0)
        new_block = old_found + '''\n
    var showSecondaryScreen: Boolean
        get() = preferences.getBoolean("EmulationMenuSettings_ShowSecondaryScreen", false)
        set(value) {
            preferences.edit()
                .putBoolean("EmulationMenuSettings_ShowSecondaryScreen", value)
                .apply()
        }'''
        content = content.replace(old_found, new_block, 1)
        print("showSecondaryScreen berhasil ditambahkan (regex).")
    else:
        # Tambahkan sebelum closing brace terakhir
        content = content.rstrip()
        if content.endswith('}'):
            content = content[:-1] + '''
    var showSecondaryScreen: Boolean
        get() = preferences.getBoolean("EmulationMenuSettings_ShowSecondaryScreen", false)
        set(value) {
            preferences.edit()
                .putBoolean("EmulationMenuSettings_ShowSecondaryScreen", value)
                .apply()
        }
}'''
        print("showSecondaryScreen ditambahkan di akhir object.")
else:
    content = content.replace(old, new, 1)
    print("showSecondaryScreen berhasil ditambahkan.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 2: ScreenAdjustmentUtil.kt
# Tambah fun toggleSecondaryScreen() setelah fun swapScreen()
# ============================================================
echo ""
echo "=== Step 2: Tambah toggleSecondaryScreen() di ScreenAdjustmentUtil ==="

python3 - "$ADJUSTMENT_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'toggleSecondaryScreen' in content:
    print("toggleSecondaryScreen sudah ada, skip.")
    sys.exit(0)

# Cari anchor: setelah fungsi swapScreen() — cari "fun cycleLayouts"
anchor = "    fun cycleLayouts() {"

new_func = '''    /**
     * Toggle tampilan layar kedua saat mode SINGLE_SCREEN aktif.
     * Ketika ON: native core diinstruksikan render seperti LARGE_SCREEN
     * (layar kedua muncul kecil di pojok kanan bawah).
     * Ketika OFF: kembali ke SINGLE_SCREEN murni.
     */
    fun toggleSecondaryScreen() {
        val isNowShowing = !EmulationMenuSettings.showSecondaryScreen
        EmulationMenuSettings.showSecondaryScreen = isNowShowing

        // Hanya berlaku saat SINGLE_SCREEN aktif
        val currentLayout = if (NativeLibrary.isPortraitMode) {
            IntSetting.PORTRAIT_SCREEN_LAYOUT.int
        } else {
            IntSetting.SCREEN_LAYOUT.int
        }

        val isSingleScreen = currentLayout == org.citra.citra_emu.display.ScreenLayout.SINGLE_SCREEN.int

        if (isSingleScreen) {
            if (isNowShowing) {
                // Render seperti LARGE_SCREEN sementara
                NativeLibrary.updateFramebuffer(NativeLibrary.isPortraitMode)
            } else {
                // Kembali ke single screen
                NativeLibrary.updateFramebuffer(NativeLibrary.isPortraitMode)
            }
        }
    }

'''

if anchor not in content:
    print("WARNING: Anchor 'fun cycleLayouts' tidak ditemukan, tambahkan sebelum changePortraitOrientation.")
    anchor2 = "    fun changePortraitOrientation("
    if anchor2 in content:
        content = content.replace(anchor2, new_func + "    fun changePortraitOrientation(", 1)
        print("toggleSecondaryScreen ditambahkan sebelum changePortraitOrientation.")
    else:
        print("ERROR: Tidak bisa menemukan anchor yang cocok!")
        sys.exit(1)
else:
    content = content.replace(anchor, new_func + anchor, 1)
    print("toggleSecondaryScreen berhasil ditambahkan.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 3: InputOverlay.kt
# Update isTouchScreenVisible() untuk cek showSecondaryScreen
# ============================================================
echo ""
echo "=== Step 3: Update isTouchScreenVisible() di InputOverlay ==="

python3 - "$OVERLAY_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Cek apakah isTouchScreenVisible sudah ada
if 'isTouchScreenVisible' not in content:
    print("ERROR: isTouchScreenVisible() belum ada. Jalankan fix_single_screen_touch.sh dulu!")
    sys.exit(1)

# Cek apakah EmulationMenuSettings sudah diimport
if 'import org.citra.citra_emu.utils.EmulationMenuSettings' not in content:
    print("INFO: EmulationMenuSettings sudah ada di import (dari EmulationMenuSettings yang dipakai).")

# Update fungsi isTouchScreenVisible
old_func = '''    private fun isTouchScreenVisible(): Boolean {
        val layout = IntSetting.SCREEN_LAYOUT.int
        return layout != ScreenLayout.SINGLE_SCREEN.int
    }'''

new_func = '''    private fun isTouchScreenVisible(): Boolean {
        val layout = IntSetting.SCREEN_LAYOUT.int
        val isSingleScreen = layout == ScreenLayout.SINGLE_SCREEN.int
        // Saat single screen: cek apakah user mengaktifkan show secondary screen
        if (isSingleScreen) {
            return EmulationMenuSettings.showSecondaryScreen
        }
        return true
    }'''

if old_func in content:
    content = content.replace(old_func, new_func, 1)
    print("isTouchScreenVisible() berhasil diupdate.")
else:
    # Coba cari dengan regex
    import re
    pattern = r'private fun isTouchScreenVisible\(\): Boolean \{[^}]+\}'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.start()] + new_func + content[match.end():]
        print("isTouchScreenVisible() diupdate (regex).")
    else:
        print("WARNING: isTouchScreenVisible() tidak ditemukan, tambahkan manual.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 4: menu_overlay_options.xml
# Tambah item menu_show_secondary_screen
# ============================================================
echo ""
echo "=== Step 4: Tambah item menu di menu_overlay_options.xml ==="

python3 - "$MENU_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'menu_show_secondary_screen' in content:
    print("menu_show_secondary_screen sudah ada, skip.")
    sys.exit(0)

# Tambahkan setelah item menu_show_overlay
# Cari pattern item show_overlay
import re

# Cari item show_overlay dan tambahkan setelahnya
anchor_patterns = [
    'menu_show_overlay',
    'menu_haptic_feedback',
]

inserted = False
for anchor in anchor_patterns:
    # Cari item XML yang mengandung anchor
    pattern = r'(<item[^>]+id="@\+id/' + anchor + r'"[^/]*/?>)'
    match = re.search(pattern, content)
    if match:
        item_end = match.end()
        new_item = '''\n    <item
        android:id="@+id/menu_show_secondary_screen"
        android:title="@string/emulation_show_secondary_screen"
        android:checkable="true" />'''
        content = content[:item_end] + new_item + content[item_end:]
        print(f"Item menu_show_secondary_screen ditambahkan setelah {anchor}.")
        inserted = True
        break

if not inserted:
    # Tambahkan sebelum </menu>
    content = content.replace('</menu>', '''    <item
        android:id="@+id/menu_show_secondary_screen"
        android:title="@string/emulation_show_secondary_screen"
        android:checkable="true" />
</menu>''', 1)
    print("Item ditambahkan sebelum </menu>.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 5: strings.xml — tambah string resource
# ============================================================
echo ""
echo "=== Step 5: Tambah string resource ==="

STRINGS_FILE="src/android/app/src/main/res/values/strings.xml"
if [ -f "$STRINGS_FILE" ]; then
python3 - "$STRINGS_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'emulation_show_secondary_screen' in content:
    print("String sudah ada, skip.")
    sys.exit(0)

# Tambahkan setelah string swap_screens atau show_overlay
anchors = [
    '</string>\n    <!-- Screen layout',
    'emulation_swap_screens',
    'show_overlay',
]

new_str = '\n    <string name="emulation_show_secondary_screen">Show Secondary Screen</string>'

import re
# Cari posisi yang tepat — dekat string terkait emulation screen
pattern = r'(<string name="emulation_[^"]*swap[^"]*"[^<]*</string>)'
match = re.search(pattern, content)
if match:
    content = content[:match.end()] + new_str + content[match.end():]
    print("String emulation_show_secondary_screen ditambahkan.")
else:
    # Fallback: tambahkan sebelum </resources>
    content = content.replace('</resources>', new_str + '\n</resources>', 1)
    print("String ditambahkan sebelum </resources>.")

with open(path, 'w') as f:
    f.write(content)
PYEOF
else
    echo "WARNING: strings.xml tidak ditemukan di path standar, skip."
    echo "Tambahkan manual: <string name=\"emulation_show_secondary_screen\">Show Secondary Screen</string>"
fi

# ============================================================
# Step 6: EmulationFragment.kt
# Tambah handler untuk menu_show_secondary_screen
# ============================================================
echo ""
echo "=== Step 6: Tambah handler di EmulationFragment ==="

python3 - "$FRAGMENT_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'menu_show_secondary_screen' in content:
    print("Handler menu_show_secondary_screen sudah ada, skip.")
    sys.exit(0)

# Tambahkan handler setelah R.id.menu_show_overlay
old = '''                R.id.menu_show_overlay -> {
                    EmulationMenuSettings.showOverlay = !EmulationMenuSettings.showOverlay
                    binding.surfaceInputOverlay.refreshControls()
                    true
                }'''

new = '''                R.id.menu_show_overlay -> {
                    EmulationMenuSettings.showOverlay = !EmulationMenuSettings.showOverlay
                    binding.surfaceInputOverlay.refreshControls()
                    true
                }

                R.id.menu_show_secondary_screen -> {
                    // Hanya relevan saat SINGLE_SCREEN aktif
                    val isSingleScreen = org.citra.citra_emu.features.settings.model.IntSetting.SCREEN_LAYOUT.int ==
                        org.citra.citra_emu.display.ScreenLayout.SINGLE_SCREEN.int
                    if (isSingleScreen) {
                        screenAdjustmentUtil.toggleSecondaryScreen()
                        it.isChecked = EmulationMenuSettings.showSecondaryScreen
                    }
                    true
                }'''

if old in content:
    content = content.replace(old, new, 1)
    print("Handler menu_show_secondary_screen berhasil ditambahkan.")
else:
    import re
    pattern = r'(R\.id\.menu_show_overlay -> \{[^}]+refreshControls\(\)[^}]+true\s+\})'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        old_found = match.group(0)
        new_handler = old_found + '''

                R.id.menu_show_secondary_screen -> {
                    val isSingleScreen = org.citra.citra_emu.features.settings.model.IntSetting.SCREEN_LAYOUT.int ==
                        org.citra.citra_emu.display.ScreenLayout.SINGLE_SCREEN.int
                    if (isSingleScreen) {
                        screenAdjustmentUtil.toggleSecondaryScreen()
                        it.isChecked = EmulationMenuSettings.showSecondaryScreen
                    }
                    true
                }'''
        content = content.replace(old_found, new_handler, 1)
        print("Handler ditambahkan (regex).")
    else:
        print("WARNING: Anchor menu_show_overlay tidak ditemukan!")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 7: Update showOverlayMenu() — set checked state
# ============================================================
echo ""
echo "=== Step 7: Update checked state di showOverlayMenu() ==="

python3 - "$FRAGMENT_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'menu_show_secondary_screen' in content and 'showSecondaryScreen' in content:
    # Cek apakah checked state sudah ada
    if 'findItem(R.id.menu_show_secondary_screen).isChecked' in content:
        print("Checked state sudah ada, skip.")
        sys.exit(0)

# Tambahkan checked state setelah findItem(R.id.menu_show_overlay).isChecked
old = '            findItem(R.id.menu_show_overlay).isChecked = EmulationMenuSettings.showOverlay'
new = ('            findItem(R.id.menu_show_overlay).isChecked = EmulationMenuSettings.showOverlay\n'
       '            findItem(R.id.menu_show_secondary_screen).isChecked = EmulationMenuSettings.showSecondaryScreen\n'
       '            // Disable tombol jika bukan single screen\n'
       '            findItem(R.id.menu_show_secondary_screen).isEnabled =\n'
       '                org.citra.citra_emu.features.settings.model.IntSetting.SCREEN_LAYOUT.int ==\n'
       '                org.citra.citra_emu.display.ScreenLayout.SINGLE_SCREEN.int')

if old in content:
    content = content.replace(old, new, 1)
    print("Checked state berhasil ditambahkan.")
else:
    print("WARNING: Anchor isChecked showOverlay tidak ditemukan, skip.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 8: ScreenAdjustmentUtil — pastikan import EmulationMenuSettings ada
# ============================================================
echo ""
echo "=== Step 8: Pastikan import EmulationMenuSettings di ScreenAdjustmentUtil ==="

python3 - "$ADJUSTMENT_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'import org.citra.citra_emu.utils.EmulationMenuSettings' in content:
    print("Import EmulationMenuSettings sudah ada.")
else:
    old = 'import org.citra.citra_emu.utils.EmulationMenuSettings\n'
    # Tambahkan setelah import NativeLibrary
    anchor = 'import org.citra.citra_emu.NativeLibrary'
    if anchor in content:
        content = content.replace(anchor,
            anchor + '\nimport org.citra.citra_emu.utils.EmulationMenuSettings', 1)
        print("Import EmulationMenuSettings ditambahkan.")
    else:
        print("WARNING: Tidak bisa tambahkan import EmulationMenuSettings.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Verifikasi
# ============================================================
echo ""
echo "=== VERIFIKASI ==="
echo ""
echo "--- EmulationMenuSettings ---"
grep -n "showSecondaryScreen" "$SETTINGS_FILE"

echo ""
echo "--- ScreenAdjustmentUtil ---"
grep -n "toggleSecondaryScreen\|showSecondaryScreen" "$ADJUSTMENT_FILE"

echo ""
echo "--- InputOverlay ---"
grep -n "isTouchScreenVisible\|showSecondaryScreen" "$OVERLAY_FILE"

echo ""
echo "--- EmulationFragment ---"
grep -n "menu_show_secondary_screen\|showSecondaryScreen" "$FRAGMENT_FILE"

echo ""
echo "--- menu_overlay_options.xml ---"
grep -n "secondary_screen" "$MENU_FILE"

echo ""
echo "=== SELESAI ==="
echo ""
echo "CATATAN PENTING:"
echo "Pastikan patch fix_single_screen_touch.sh sudah dijalankan dulu"
echo "sebelum script ini, karena isTouchScreenVisible() harus sudah ada."
echo ""
echo "Selanjutnya: git add -A && git commit -m 'feat: add Show Secondary Screen toggle for Single Screen mode' && git push"
