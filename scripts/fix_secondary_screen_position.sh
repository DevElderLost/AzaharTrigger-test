#!/usr/bin/env bash
# ============================================================
# fix_secondary_screen_position.sh
#
# Update: Posisi layar kedua saat Show Secondary Screen
# menggunakan nilai dari Custom Layout (LANDSCAPE_BOTTOM_X/Y/WIDTH/HEIGHT)
# bukan hardcoded seperti LARGE_SCREEN.
#
# Yang diubah:
# - ScreenAdjustmentUtil.kt: toggleSecondaryScreen() diupdate
#   untuk membaca IntSetting.LANDSCAPE_BOTTOM_X/Y/WIDTH/HEIGHT
#   dan memanggil NativeLibrary.reloadSettings() +
#   updateFramebuffer() supaya native core re-render dengan
#   posisi dari custom layout.
# ============================================================

set -e

ADJUSTMENT_FILE="src/android/app/src/main/java/org/citra/citra_emu/display/ScreenAdjustmentUtil.kt"

if [ ! -f "$ADJUSTMENT_FILE" ]; then
    echo "ERROR: File tidak ditemukan: $ADJUSTMENT_FILE"
    exit 1
fi

echo "=== Backup ==="
cp "$ADJUSTMENT_FILE" "${ADJUSTMENT_FILE}.bak4"
echo "Backup: ${ADJUSTMENT_FILE}.bak4"

# ============================================================
# Update fungsi toggleSecondaryScreen()
# Logika baru:
# 1. Toggle state showSecondaryScreen
# 2. Jika SINGLE_SCREEN:
#    - Kalau ON: baca LANDSCAPE_BOTTOM_X/Y/WIDTH/HEIGHT dari
#      IntSetting (nilai custom layout), terapkan ke native
#      dengan mengubah sementara SCREEN_LAYOUT ke CUSTOM_LAYOUT
#      supaya native core merender layar kedua di posisi tsb
#    - Kalau OFF: kembalikan SCREEN_LAYOUT ke SINGLE_SCREEN
# 3. reloadSettings() + updateFramebuffer()
# ============================================================
echo ""
echo "=== Update toggleSecondaryScreen() ==="

python3 - "$ADJUSTMENT_FILE" << 'PYEOF'
import sys
import re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Cari dan replace fungsi toggleSecondaryScreen yang sudah ada
old_pattern = r'    /\*\*\s*\n.*?Toggle tampilan layar kedua.*?\.isPortraitMode\)\s*\}\s*\}\s*\}'
match = re.search(old_pattern, content, re.DOTALL)

new_func = '''    /**
     * Toggle tampilan layar kedua saat mode SINGLE_SCREEN aktif.
     *
     * Ketika ON:
     *   - Baca posisi layar kedua dari setting Custom Layout
     *     (IntSetting.LANDSCAPE_BOTTOM_X/Y/WIDTH/HEIGHT)
     *   - Terapkan sementara SCREEN_LAYOUT = CUSTOM_LAYOUT
     *     supaya native core merender layar kedua di posisi tersebut
     *   - Touch input ke layar kedua ikut aktif
     *
     * Ketika OFF:
     *   - Kembalikan SCREEN_LAYOUT ke SINGLE_SCREEN
     *   - Touch input ke layar kedua diblokir kembali
     */
    fun toggleSecondaryScreen() {
        val isNowShowing = !EmulationMenuSettings.showSecondaryScreen
        EmulationMenuSettings.showSecondaryScreen = isNowShowing

        // Hanya berlaku saat SINGLE_SCREEN aktif
        val isSingleScreen = if (NativeLibrary.isPortraitMode) {
            IntSetting.PORTRAIT_SCREEN_LAYOUT.int == ScreenLayout.SINGLE_SCREEN.int
        } else {
            IntSetting.SCREEN_LAYOUT.int == ScreenLayout.SINGLE_SCREEN.int
        }

        if (!isSingleScreen) return

        if (isNowShowing) {
            // Terapkan CUSTOM_LAYOUT sementara supaya layar kedua
            // dirender di posisi yang sama dengan Custom Layout setting
            // Native core akan membaca LANDSCAPE_BOTTOM_X/Y/WIDTH/HEIGHT
            // dari settings untuk menentukan posisi & ukuran layar kedua
            if (NativeLibrary.isPortraitMode) {
                IntSetting.PORTRAIT_SCREEN_LAYOUT.int = ScreenLayout.CUSTOM_LAYOUT.int
                settings.saveSetting(IntSetting.PORTRAIT_SCREEN_LAYOUT, SettingsFile.FILE_NAME_CONFIG)
            } else {
                IntSetting.SCREEN_LAYOUT.int = ScreenLayout.CUSTOM_LAYOUT.int
                settings.saveSetting(IntSetting.SCREEN_LAYOUT, SettingsFile.FILE_NAME_CONFIG)
            }
        } else {
            // Kembalikan ke SINGLE_SCREEN
            if (NativeLibrary.isPortraitMode) {
                IntSetting.PORTRAIT_SCREEN_LAYOUT.int = ScreenLayout.SINGLE_SCREEN.int
                settings.saveSetting(IntSetting.PORTRAIT_SCREEN_LAYOUT, SettingsFile.FILE_NAME_CONFIG)
            } else {
                IntSetting.SCREEN_LAYOUT.int = ScreenLayout.SINGLE_SCREEN.int
                settings.saveSetting(IntSetting.SCREEN_LAYOUT, SettingsFile.FILE_NAME_CONFIG)
            }
        }

        // Reload dan refresh render
        NativeLibrary.reloadSettings()
        NativeLibrary.updateFramebuffer(NativeLibrary.isPortraitMode)
    }'''

if match:
    content = content[:match.start()] + new_func + content[match.end():]
    print("toggleSecondaryScreen() berhasil diupdate.")
else:
    # Coba cari dengan pattern lebih sederhana
    old_simple = '    fun toggleSecondaryScreen() {'
    if old_simple in content:
        # Cari seluruh blok fungsi
        start = content.index(old_simple)
        # Cari closing brace yang matching
        depth = 0
        i = start
        found_open = False
        end = start
        while i < len(content):
            if content[i] == '{':
                depth += 1
                found_open = True
            elif content[i] == '}':
                depth -= 1
                if found_open and depth == 0:
                    end = i + 1
                    break
            i += 1
        
        if end > start:
            content = content[:start] + new_func + content[end:]
            print("toggleSecondaryScreen() diupdate (brace matching).")
        else:
            print("ERROR: Tidak bisa menemukan akhir fungsi.")
            sys.exit(1)
    else:
        # Fungsi belum ada sama sekali — tambahkan
        print("INFO: toggleSecondaryScreen() belum ada, menambahkan baru.")
        anchor = "    fun cycleLayouts() {"
        if anchor not in content:
            anchor = "    fun changePortraitOrientation("
        if anchor in content:
            content = content.replace(anchor, new_func + "\n\n" + anchor, 1)
            print("toggleSecondaryScreen() ditambahkan.")
        else:
            print("ERROR: Tidak bisa menemukan anchor.")
            sys.exit(1)

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Pastikan import ScreenLayout dan SettingsFile ada
# ============================================================
echo ""
echo "=== Cek import yang diperlukan ==="

python3 - "$ADJUSTMENT_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

imports_needed = {
    'import org.citra.citra_emu.display.ScreenLayout':
        'import org.citra.citra_emu.NativeLibrary',
    'import org.citra.citra_emu.features.settings.utils.SettingsFile':
        'import org.citra.citra_emu.NativeLibrary',
    'import org.citra.citra_emu.features.settings.model.IntSetting':
        'import org.citra.citra_emu.NativeLibrary',
}

for imp, anchor in imports_needed.items():
    if imp not in content:
        if anchor in content:
            content = content.replace(anchor, anchor + '\n' + imp, 1)
            print(f"Ditambahkan: {imp}")
        else:
            print(f"WARNING: Tidak bisa tambahkan {imp}")
    else:
        print(f"Sudah ada: {imp}")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Update isTouchScreenVisible() di InputOverlay.kt
# Sekarang saat showSecondaryScreen = ON, layout sudah diubah
# ke CUSTOM_LAYOUT, jadi pengecekan SINGLE_SCREEN akan false
# dan touch otomatis aktif. Tapi perlu fallback untuk
# memastikan tetap benar.
# ============================================================
echo ""
echo "=== Update isTouchScreenVisible() di InputOverlay ==="

OVERLAY_FILE="src/android/app/src/main/java/org/citra/citra_emu/overlay/InputOverlay.kt"

python3 - "$OVERLAY_FILE" << 'PYEOF'
import sys
import re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Cari dan update isTouchScreenVisible
old_pattern = r'    private fun isTouchScreenVisible\(\): Boolean \{.*?\}'
match = re.search(old_pattern, content, re.DOTALL)

new_func = '''    private fun isTouchScreenVisible(): Boolean {
        val layout = IntSetting.SCREEN_LAYOUT.int
        val isSingleScreen = layout == ScreenLayout.SINGLE_SCREEN.int
        // Saat single screen: cek apakah user mengaktifkan show secondary screen
        // Ketika showSecondaryScreen = ON, layout sudah diubah ke CUSTOM_LAYOUT
        // oleh toggleSecondaryScreen(), jadi isSingleScreen = false otomatis.
        // Guard ini sebagai fallback keamanan tambahan.
        if (isSingleScreen) {
            return EmulationMenuSettings.showSecondaryScreen
        }
        return true
    }'''

if match:
    content = content[:match.start()] + new_func + content[match.end():]
    print("isTouchScreenVisible() diupdate.")
else:
    print("INFO: isTouchScreenVisible() tidak ditemukan, sudah benar atau belum ada.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Verifikasi
# ============================================================
echo ""
echo "=== VERIFIKASI ==="

echo ""
echo "--- toggleSecondaryScreen() di ScreenAdjustmentUtil ---"
grep -n "toggleSecondaryScreen\|CUSTOM_LAYOUT\|SINGLE_SCREEN\|LANDSCAPE_BOTTOM\|reloadSettings\|showSecondaryScreen" "$ADJUSTMENT_FILE"

echo ""
echo "--- Import di ScreenAdjustmentUtil ---"
grep -n "^import" "$ADJUSTMENT_FILE" | head -15

echo ""
echo "=== SELESAI ==="
echo ""
echo "LOGIKA BARU:"
echo "  Single Screen + tombol ON:"
echo "    → SCREEN_LAYOUT diubah ke CUSTOM_LAYOUT sementara"
echo "    → Native core membaca LANDSCAPE_BOTTOM_X/Y/WIDTH/HEIGHT"
echo "    → Layar kedua muncul di posisi yang sama dengan Custom Layout setting"
echo "    → Touch input aktif"
echo ""
echo "  Single Screen + tombol OFF:"  
echo "    → SCREEN_LAYOUT dikembalikan ke SINGLE_SCREEN"
echo "    → Layar kedua hilang"
echo "    → Touch input diblokir"
echo ""
echo "git add -A && git commit -m 'fix: secondary screen uses custom layout position' && git push"
