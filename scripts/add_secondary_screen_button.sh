#!/usr/bin/env bash
# ============================================================
# add_secondary_screen_button.sh
#
# Fitur: Tombol overlay "Show Secondary Screen"
# - Punya icon PNG (pakai button_swap sebagai base, atau buat baru)
# - Posisi bisa digeser di edit mode
# - Scale mengikuti sistem controlScale
# - Toggle: ON = layar kedua muncul, OFF = layar kedua hilang
# - Hanya aktif logikanya saat SINGLE_SCREEN mode
# - buttonToggle index: 21 (setelah combo buttons 16-20)
#
# URUTAN EKSEKUSI:
# 1. fix_single_screen_touch.sh   (harus sudah jalan)
# 2. add_show_secondary_screen.sh (harus sudah jalan)
# 3. Script ini
# ============================================================

set -e

OVERLAY_FILE="src/android/app/src/main/java/org/citra/citra_emu/overlay/InputOverlay.kt"
NATIVE_FILE="src/android/app/src/main/java/org/citra/citra_emu/NativeLibrary.kt"
FRAGMENT_FILE="src/android/app/src/main/java/org/citra/citra_emu/fragments/EmulationFragment.kt"
STRINGS_FILE="src/android/app/src/main/res/values/strings.xml"
DRAWABLE_DIR="src/android/app/src/main/res/drawable-xxxhdpi"

for f in "$OVERLAY_FILE" "$NATIVE_FILE" "$FRAGMENT_FILE"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: File tidak ditemukan: $f"
        exit 1
    fi
done

echo "=== Backup file ==="
cp "$OVERLAY_FILE" "${OVERLAY_FILE}.bak3"
cp "$NATIVE_FILE" "${NATIVE_FILE}.bak3"
cp "$FRAGMENT_FILE" "${FRAGMENT_FILE}.bak3"
echo "Backup selesai."

# ============================================================
# Step 1: Buat icon PNG untuk tombol
# Gunakan button_swap.png yang sudah ada sebagai template,
# copy dengan nama baru. Nanti bisa diganti icon custom.
# ============================================================
echo ""
echo "=== Step 1: Buat icon button_secondary_screen.png ==="

if [ -f "$DRAWABLE_DIR/button_secondary_screen.png" ]; then
    echo "Icon sudah ada, skip."
else
    if [ -f "$DRAWABLE_DIR/button_swap.png" ]; then
        cp "$DRAWABLE_DIR/button_swap.png" "$DRAWABLE_DIR/button_secondary_screen.png"
        cp "$DRAWABLE_DIR/button_swap_pressed.png" "$DRAWABLE_DIR/button_secondary_screen_pressed.png"
        echo "Icon dibuat dari button_swap.png (placeholder)."
        echo "CATATAN: Ganti dengan icon custom jika diperlukan."
    else
        # Fallback ke button_home
        if [ -f "$DRAWABLE_DIR/button_home.png" ]; then
            cp "$DRAWABLE_DIR/button_home.png" "$DRAWABLE_DIR/button_secondary_screen.png"
            if [ -f "$DRAWABLE_DIR/button_home_pressed.png" ]; then
                cp "$DRAWABLE_DIR/button_home_pressed.png" "$DRAWABLE_DIR/button_secondary_screen_pressed.png"
            else
                cp "$DRAWABLE_DIR/button_home.png" "$DRAWABLE_DIR/button_secondary_screen_pressed.png"
            fi
            echo "Icon dibuat dari button_home.png (fallback)."
        else
            echo "WARNING: Tidak ada icon base yang cocok. Buat icon manual."
        fi
    fi
fi

# ============================================================
# Step 2: Tambah konstanta BUTTON_SECONDARY_SCREEN di NativeLibrary.kt
# Pakai nilai 900 (setelah BUTTON_SWAP=800)
# ============================================================
echo ""
echo "=== Step 2: Tambah konstanta BUTTON_SECONDARY_SCREEN di NativeLibrary ==="

python3 - "$NATIVE_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'BUTTON_SECONDARY_SCREEN' in content:
    print("Konstanta sudah ada, skip.")
    sys.exit(0)

# Tambahkan setelah BUTTON_SWAP = 800
old = 'const val BUTTON_SWAP = 800'
new = ('const val BUTTON_SWAP = 800\n'
       '        const val BUTTON_SECONDARY_SCREEN = 900')

if old in content:
    content = content.replace(old, new, 1)
    print("BUTTON_SECONDARY_SCREEN = 900 berhasil ditambahkan.")
else:
    # Coba tanpa indentasi
    import re
    match = re.search(r'(const val BUTTON_SWAP\s*=\s*800)', content)
    if match:
        content = content[:match.end()] + '\n        const val BUTTON_SECONDARY_SCREEN = 900' + content[match.end():]
        print("BUTTON_SECONDARY_SCREEN ditambahkan (regex).")
    else:
        print("ERROR: BUTTON_SWAP = 800 tidak ditemukan!")
        sys.exit(1)

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 3: InputOverlay.kt — tambah di initializeOverlayButton scale
# Tombol secondary screen pakai scale 0.08f (sama dengan SWAP/HOME)
# ============================================================
echo ""
echo "=== Step 3: Tambah scale untuk BUTTON_SECONDARY_SCREEN ==="

python3 - "$OVERLAY_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'BUTTON_SECONDARY_SCREEN' in content and 'scale' in content:
    # Cek apakah sudah ada di blok scale
    import re
    if re.search(r'BUTTON_SECONDARY_SCREEN.*->.*0\.08f', content):
        print("Scale BUTTON_SECONDARY_SCREEN sudah ada, skip.")
        sys.exit(0)

# Cari blok scale — tambahkan BUTTON_SECONDARY_SCREEN bersama BUTTON_SWAP
# Pattern: NativeLibrary.ButtonType.BUTTON_SWAP -> 0.08f
old = 'NativeLibrary.ButtonType.BUTTON_SWAP -> 0.08f'
new = ('NativeLibrary.ButtonType.BUTTON_SWAP,\n'
       '                    NativeLibrary.ButtonType.BUTTON_SECONDARY_SCREEN -> 0.08f')

if old in content:
    content = content.replace(old, new, 1)
    print("Scale BUTTON_SECONDARY_SCREEN ditambahkan.")
else:
    # Cari dengan pattern lebih fleksibel
    import re
    # Cari baris yang mengandung BUTTON_SWAP -> 0.08f atau BUTTON_SWAP -> 0.08f
    pattern = r'(NativeLibrary\.ButtonType\.BUTTON_SWAP\s*->\s*0\.08f)'
    match = re.search(pattern, content)
    if match:
        old_text = match.group(0)
        new_text = ('NativeLibrary.ButtonType.BUTTON_SWAP,\n'
                   '                    NativeLibrary.ButtonType.BUTTON_SECONDARY_SCREEN -> 0.08f')
        content = content.replace(old_text, new_text, 1)
        print("Scale ditambahkan (regex).")
    else:
        # Tambahkan bersama BUTTON_HOME dengan nilai sama
        pattern2 = r'(NativeLibrary\.ButtonType\.BUTTON_HOME.*?->\s*0\.08f)'
        match2 = re.search(pattern2, content, re.DOTALL)
        if match2:
            old_text = match2.group(0)
            new_text = old_text + ',\n                    NativeLibrary.ButtonType.BUTTON_SECONDARY_SCREEN -> 0.08f'
            # Ini tidak benar, kita perlu menambahkan sebagai case baru
            # Tambahkan setelah blok BUTTON_SWAP
            print("WARNING: Struktur scale berbeda, tambahkan manual.")
        else:
            print("WARNING: Tidak bisa menemukan blok scale, tambahkan manual.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 4: InputOverlay.kt — tambah di addOverlayControls()
# buttonToggle index 21
# ============================================================
echo ""
echo "=== Step 4: Tambah button di addOverlayControls() ==="

python3 - "$OVERLAY_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'buttonToggle21' in content and 'BUTTON_SECONDARY_SCREEN' in content:
    print("Button sudah ada di addOverlayControls, skip.")
    sys.exit(0)

# Cari anchor: blok buttonToggle14 (BUTTON_SWAP) atau buttonToggle15 (turbo)
# Tambahkan setelah blok terakhir (combo buttons, buttonToggle15 atau setelah 20)

# Cari anchor setelah combo buttons (buttonToggle15 atau akhir addOverlayControls)
import re

# Cari pola: if (preferences.getBoolean("buttonToggle15", false)) {
# yang merupakan button terakhir sebelum combo
anchor_pattern = r'(if \(preferences\.getBoolean\("buttonToggle15",\s*false\)\) \{[^}]+\})'
match = re.search(anchor_pattern, content, re.DOTALL)

new_button_block = '''
                if (preferences.getBoolean("buttonToggle21", false)) {
                    overlayButtons.add(
                        initializeOverlayButton(
                            context,
                            R.drawable.button_secondary_screen,
                            R.drawable.button_secondary_screen_pressed,
                            NativeLibrary.ButtonType.BUTTON_SECONDARY_SCREEN,
                            orientation
                        )
                    )
                }'''

if match:
    old_text = match.group(0)
    content = content.replace(old_text, old_text + new_button_block, 1)
    print("Button BUTTON_SECONDARY_SCREEN ditambahkan setelah buttonToggle15.")
else:
    # Coba cari setelah combo button block (buttonToggle20)
    anchor2_pattern = r'(// — Combo Buttons.*?buttonToggle20.*?\}.*?\})'
    match2 = re.search(anchor2_pattern, content, re.DOTALL)
    if match2:
        old_text = match2.group(0)
        content = content.replace(old_text, old_text + new_button_block, 1)
        print("Button ditambahkan setelah combo buttons.")
    else:
        # Cari akhir fungsi addOverlayControls — sebelum return atau closing brace
        # Tambahkan setelah buttonToggle terakhir yang ada
        last_toggle = None
        for i in range(20, 14, -1):
            if f'buttonToggle{i}' in content:
                last_toggle = i
                break
        
        if last_toggle:
            # Cari blok terakhir buttonToggle
            pattern3 = rf'(if \(preferences\.getBoolean\("buttonToggle{last_toggle}",.*?\n.*?\n.*?\}})'
            match3 = re.search(pattern3, content, re.DOTALL)
            if match3:
                old_text = match3.group(0)
                content = content.replace(old_text, old_text + new_button_block, 1)
                print(f"Button ditambahkan setelah buttonToggle{last_toggle}.")
            else:
                print(f"WARNING: Tidak bisa parse blok buttonToggle{last_toggle}.")
        else:
            print("WARNING: Tidak bisa menemukan anchor untuk addOverlayControls.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 5: InputOverlay.kt — tambah di onTouch handler
# Tombol secondary screen harus handle ACTION_DOWN untuk toggle
# ============================================================
echo ""
echo "=== Step 5: Tambah handler onTouch untuk BUTTON_SECONDARY_SCREEN ==="

python3 - "$OVERLAY_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'BUTTON_SECONDARY_SCREEN' in content and 'toggleSecondaryScreen' in content:
    import re
    if re.search(r'BUTTON_SECONDARY_SCREEN.*toggleSecondaryScreen', content, re.DOTALL):
        print("Handler onTouch sudah ada, skip.")
        sys.exit(0)

# Cari handler BUTTON_SWAP di onTouch — tambahkan SECONDARY_SCREEN di sana
# Pattern dari screenshot: if (button.id == NativeLibrary.ButtonType.BUTTON_SWAP && button.status == NativeLibrary.ButtonState.PRESSED)
import re

pattern = r'(if \(button\.id == NativeLibrary\.ButtonType\.BUTTON_SWAP\s*&&\s*button\.status == NativeLibrary\.ButtonState\.PRESSED\)\s*\{[^}]+\})'
match = re.search(pattern, content, re.DOTALL)

new_handler = '''
                    if (button.id == NativeLibrary.ButtonType.BUTTON_SECONDARY_SCREEN &&
                        button.status == NativeLibrary.ButtonState.PRESSED) {
                        settingsViewModel.settings.let {
                            (context as? android.app.Activity)?.let { activity ->
                                org.citra.citra_emu.display.ScreenAdjustmentUtil(
                                    activity,
                                    activity.windowManager,
                                    it
                                ).toggleSecondaryScreen()
                            }
                        }
                    }'''

if match:
    old_text = match.group(0)
    content = content.replace(old_text, old_text + new_handler, 1)
    print("Handler BUTTON_SECONDARY_SCREEN ditambahkan.")
else:
    print("WARNING: Handler BUTTON_SWAP tidak ditemukan, coba cari pola lain.")
    # Coba cari di baris 173 area (dari screenshot sebelumnya)
    pattern2 = r'(NativeLibrary\.ButtonType\.BUTTON_SWAP\s*&&\s*button\.status.*?PRESSED.*?\{.*?\})'
    match2 = re.search(pattern2, content, re.DOTALL)
    if match2:
        old_text = match2.group(0)
        content = content.replace(old_text, old_text + new_handler, 1)
        print("Handler ditambahkan (fallback regex).")
    else:
        print("WARNING: Tidak bisa tambah handler otomatis, perlu manual.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 6: InputOverlay.kt — tambah di resetButtonPlacement()
# Posisi default: pojok kanan bawah, mirip BUTTON_SWAP
# ============================================================
echo ""
echo "=== Step 6: Tambah default position di resetButtonPlacement() ==="

python3 - "$OVERLAY_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'BUTTON_SECONDARY_SCREEN' in content and 'N3DS_BUTTON_SECONDARY' in content:
    print("Default position sudah ada, skip.")
    sys.exit(0)

# Dari screenshot: N3DS_BUTTON_SWAP_X, N3DS_BUTTON_SWAP_Y
# Tambahkan setelah BUTTON_SWAP landscape position
import re

# Landscape: cari baris N3DS_BUTTON_SWAP_Y dan tambahkan setelahnya
pattern = r'(NativeLibrary\.ButtonType\.BUTTON_SWAP\.toString\(\) \+ "-Y",\s+resources\.getInteger\(R\.integer\.N3DS_BUTTON_SWAP_Y\)\.toFloat\(\) / 1000 \* maxY\s+\))'
match = re.search(pattern, content)

new_position_landscape = '''
                .putFloat(
                    NativeLibrary.ButtonType.BUTTON_SECONDARY_SCREEN.toString() + "-X",
                    resources.getInteger(R.integer.N3DS_BUTTON_SWAP_X).toFloat() / 1000 * maxX - 0.05f * maxX
                )
                .putFloat(
                    NativeLibrary.ButtonType.BUTTON_SECONDARY_SCREEN.toString() + "-Y",
                    resources.getInteger(R.integer.N3DS_BUTTON_SWAP_Y).toFloat() / 1000 * maxY
                )'''

if match:
    old_text = match.group(0)
    content = content.replace(old_text, old_text + new_position_landscape, 1)
    print("Default position landscape ditambahkan.")
else:
    # Coba pattern lebih sederhana
    pattern2 = r'(BUTTON_SWAP\.toString\(\) \+ "-Y".*?maxY\s*\))'
    match2 = re.search(pattern2, content, re.DOTALL)
    if match2:
        old_text = match2.group(0)
        content = content.replace(old_text, old_text + new_position_landscape, 1)
        print("Default position ditambahkan (fallback).")
    else:
        print("WARNING: Anchor posisi BUTTON_SWAP tidak ditemukan, skip.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 7: EmulationFragment.kt — tambah buttonToggle21 di showToggleControlsDialog
# ============================================================
echo ""
echo "=== Step 7: Update showToggleControlsDialog untuk buttonToggle21 ==="

python3 - "$FRAGMENT_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Update array size dari 21 ke 22
old_size = 'val enabledButtons = BooleanArray(21)'
new_size = 'val enabledButtons = BooleanArray(22)'

if new_size in content:
    print("Array size sudah 22, skip.")
else:
    if old_size in content:
        content = content.replace(old_size, new_size, 1)
        print("Array size diupdate ke 22.")
    else:
        print("WARNING: BooleanArray(21) tidak ditemukan.")

# Update default value — index 21 default false (disabled)
old_default = '6, 7, 12, 13, 14, 15, 16, 17, 18, 19, 20 -> defaultValue = false'
new_default = '6, 7, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21 -> defaultValue = false'

if new_default in content:
    print("Default value sudah include 21, skip.")
else:
    if old_default in content:
        content = content.replace(old_default, new_default, 1)
        print("Default value index 21 ditambahkan.")

# Update resetInputOverlay loop dari 21 ke 22
old_loop = 'for (i in 0 until 21) {'
new_loop = 'for (i in 0 until 22) {'

if new_loop in content:
    print("Reset loop sudah 22, skip.")
else:
    if old_loop in content:
        content = content.replace(old_loop, new_loop, 1)
        print("Reset loop diupdate ke 22.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 8: strings.xml — tambah label tombol di array n3dsButtons
# ============================================================
echo ""
echo "=== Step 8: Update string array n3dsButtons ==="

if [ -f "$STRINGS_FILE" ]; then
python3 - "$STRINGS_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'Secondary Screen' in content and 'n3dsButtons' in content:
    print("String sudah ada di array, skip.")
    sys.exit(0)

# Tambah item ke array n3dsButtons setelah item terakhir (Combo 5)
import re
# Cari akhir array n3dsButtons
pattern = r'((<string-array name="n3dsButtons">.*?)(</string-array>))'
match = re.search(pattern, content, re.DOTALL)

if match:
    old_array = match.group(0)
    # Tambahkan item sebelum closing tag
    new_item = '        <item>Secondary Screen</item>\n    '
    new_array = old_array.replace('</string-array>', new_item + '</string-array>', 1)
    content = content.replace(old_array, new_array, 1)
    print("Item 'Secondary Screen' ditambahkan ke n3dsButtons array.")
else:
    print("WARNING: string-array n3dsButtons tidak ditemukan.")

with open(path, 'w') as f:
    f.write(content)
PYEOF
fi

# ============================================================
# Step 9: Tambah adjust scale menu item di EmulationFragment
# ============================================================
echo ""
echo "=== Step 9: Tambah menu scale untuk BUTTON_SECONDARY_SCREEN ==="

python3 - "$FRAGMENT_FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'BUTTON_SECONDARY_SCREEN' in content:
    print("Scale menu sudah ada, skip.")
    sys.exit(0)

# Tambahkan setelah menu_emulation_adjust_scale_button_swap
old = '''                R.id.menu_emulation_adjust_scale_button_swap -> {
                    showAdjustScaleDialog("controlScale-" + NativeLibrary.ButtonType.BUTTON_SWAP)
                    true
                }'''

new = '''                R.id.menu_emulation_adjust_scale_button_swap -> {
                    showAdjustScaleDialog("controlScale-" + NativeLibrary.ButtonType.BUTTON_SWAP)
                    true
                }

                R.id.menu_emulation_adjust_scale_button_secondary_screen -> {
                    showAdjustScaleDialog("controlScale-" + NativeLibrary.ButtonType.BUTTON_SECONDARY_SCREEN)
                    true
                }'''

if old in content:
    content = content.replace(old, new, 1)
    print("Scale menu BUTTON_SECONDARY_SCREEN ditambahkan.")
else:
    print("INFO: Scale menu anchor tidak ditemukan (opsional).")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Verifikasi
# ============================================================
echo ""
echo "=== VERIFIKASI ==="

echo ""
echo "--- NativeLibrary: BUTTON_SECONDARY_SCREEN ---"
grep -n "BUTTON_SECONDARY_SCREEN" "$NATIVE_FILE"

echo ""
echo "--- InputOverlay: semua referensi ---"
grep -n "BUTTON_SECONDARY_SCREEN\|buttonToggle21\|button_secondary_screen" "$OVERLAY_FILE"

echo ""
echo "--- EmulationFragment: toggle index ---"
grep -n "BooleanArray\|until 22\|21 ->" "$FRAGMENT_FILE"

echo ""
echo "--- Drawable icons ---"
ls "$DRAWABLE_DIR"/button_secondary_screen*.png 2>/dev/null && echo "Icon ada." || echo "WARNING: Icon tidak ditemukan!"

echo ""
echo "=== SELESAI ==="
echo ""
echo "URUTAN YANG BENAR:"
echo "1. bash fix_single_screen_touch.sh"
echo "2. bash add_show_secondary_screen.sh"
echo "3. bash add_secondary_screen_button.sh  ← script ini"
echo ""
echo "Selanjutnya:"
echo "git add -A && git commit -m 'feat: Show Secondary Screen overlay button with icon/scale/position' && git push"
