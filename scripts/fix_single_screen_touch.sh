#!/usr/bin/env bash
# ============================================================
# fix_single_screen_touch.sh
#
# Fix: Touch input layar kedua masih aktif saat Single Screen
#
# Root cause: InputOverlay.kt tidak mengecek screen layout
# sebelum meneruskan touch ke NativeLibrary.onTouchEvent /
# onTouchMoved. Saat SINGLE_SCREEN aktif, area bekas layar
# kedua masih bisa mengirim touch input ke native core.
#
# Fix: Tambahkan pengecekan isTouchScreenVisible() sebelum
# semua pemanggilan NativeLibrary.onTouchMoved dan
# NativeLibrary.onTouchEvent yang bersumber dari touch screen
# (bukan dari button/dpad/joystick overlay).
# ============================================================

set -e

FILE="src/android/app/src/main/java/org/citra/citra_emu/overlay/InputOverlay.kt"

if [ ! -f "$FILE" ]; then
    echo "ERROR: File tidak ditemukan: $FILE"
    echo "Pastikan kamu menjalankan script ini dari root repo."
    exit 1
fi

echo "=== Backup file asli ==="
cp "$FILE" "${FILE}.bak"
echo "Backup disimpan di ${FILE}.bak"

# ============================================================
# Step 1: Tambahkan import IntSetting jika belum ada
# ============================================================
echo ""
echo "=== Step 1: Tambahkan import IntSetting ==="

if grep -q "import org.citra.citra_emu.features.settings.model.IntSetting" "$FILE"; then
    echo "Import IntSetting sudah ada, skip."
else
    # Tambahkan setelah import NativeLibrary
    python3 - "$FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

old = "import org.citra.citra_emu.NativeLibrary"
new = ("import org.citra.citra_emu.NativeLibrary\n"
       "import org.citra.citra_emu.features.settings.model.IntSetting")

if old not in content:
    print("ERROR: Anchor import NativeLibrary tidak ditemukan!")
    sys.exit(1)

content = content.replace(old, new, 1)
with open(path, 'w') as f:
    f.write(content)
print("Import IntSetting berhasil ditambahkan.")
PYEOF
fi

# ============================================================
# Step 2: Tambahkan import ScreenLayout jika belum ada
# ============================================================
echo ""
echo "=== Step 2: Tambahkan import ScreenLayout ==="

if grep -q "import org.citra.citra_emu.display.ScreenLayout" "$FILE"; then
    echo "Import ScreenLayout sudah ada, skip."
else
    python3 - "$FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

old = "import org.citra.citra_emu.features.settings.model.IntSetting"
new = ("import org.citra.citra_emu.features.settings.model.IntSetting\n"
       "import org.citra.citra_emu.display.ScreenLayout")

if old not in content:
    print("ERROR: Anchor import IntSetting tidak ditemukan!")
    sys.exit(1)

content = content.replace(old, new, 1)
with open(path, 'w') as f:
    f.write(content)
print("Import ScreenLayout berhasil ditambahkan.")
PYEOF
fi

# ============================================================
# Step 3: Tambahkan helper function isTouchScreenVisible()
# di dalam class InputOverlay, sebelum fun onTouch
# ============================================================
echo ""
echo "=== Step 3: Tambahkan helper isTouchScreenVisible() ==="

if grep -q "fun isTouchScreenVisible" "$FILE"; then
    echo "Helper isTouchScreenVisible() sudah ada, skip."
else
    python3 - "$FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Anchor: tepat sebelum "override fun onTouch("
anchor = "    override fun onTouch("

helper = (
    "    /**\n"
    "     * Returns true jika touchscreen 3DS (layar bawah) seharusnya\n"
    "     * menerima input sentuh. Pada mode SINGLE_SCREEN, layar bawah\n"
    "     * tidak ditampilkan sehingga touch input ke area itu harus diblokir.\n"
    "     */\n"
    "    private fun isTouchScreenVisible(): Boolean {\n"
    "        val layout = IntSetting.SCREEN_LAYOUT.int\n"
    "        return layout != ScreenLayout.SINGLE_SCREEN.int\n"
    "    }\n"
    "\n"
)

if anchor not in content:
    print("ERROR: Anchor 'override fun onTouch(' tidak ditemukan!")
    sys.exit(1)

content = content.replace(anchor, helper + anchor, 1)
with open(path, 'w') as f:
    f.write(content)
print("Helper isTouchScreenVisible() berhasil ditambahkan.")
PYEOF
fi

# ============================================================
# Step 4: Guard onTouchMoved — wrap dengan isTouchScreenVisible()
# Pattern asli:
#     NativeLibrary.onTouchMoved(xPosition.toFloat(), yPosition.toFloat())
# Menjadi:
#     if (isTouchScreenVisible()) {
#         NativeLibrary.onTouchMoved(xPosition.toFloat(), yPosition.toFloat())
#     }
# ============================================================
echo ""
echo "=== Step 4: Guard NativeLibrary.onTouchMoved ==="

python3 - "$FILE" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

old = "                        NativeLibrary.onTouchMoved(xPosition.toFloat(), yPosition.toFloat())\n                        continue"
new = ("                        if (isTouchScreenVisible()) {\n"
       "                            NativeLibrary.onTouchMoved(xPosition.toFloat(), yPosition.toFloat())\n"
       "                        }\n"
       "                        continue")

if old not in content:
    # Coba variasi spasi
    old2 = "NativeLibrary.onTouchMoved(xPosition.toFloat(), yPosition.toFloat())"
    if old2 in content:
        # Wrap semua kemunculan onTouchMoved yang belum di-wrap
        import re
        pattern = r'(\s+)(NativeLibrary\.onTouchMoved\(xPosition\.toFloat\(\), yPosition\.toFloat\(\)\))'
        def replacer(m):
            indent = m.group(1)
            call = m.group(2)
            # Cek apakah sudah di-wrap
            return f"{indent}if (isTouchScreenVisible()) {{\n{indent}    {call.strip()}\n{indent}}}"
        new_content = re.sub(pattern, replacer, content)
        if new_content != content:
            content = new_content
            print("Guard onTouchMoved berhasil ditambahkan (regex fallback).")
        else:
            print("WARNING: onTouchMoved tidak berubah, mungkin sudah di-wrap.")
    else:
        print("WARNING: onTouchMoved tidak ditemukan, skip step ini.")
else:
    content = content.replace(old, new, 1)
    print("Guard onTouchMoved berhasil ditambahkan.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 5: Guard onTouchEvent untuk touch screen (ACTION_DOWN area)
# Di dalam blok: if (!isDpadPressed && !isJoystickPressed)
# Pattern asli:
#     NativeLibrary.onTouchEvent(xPosition.toFloat(), yPosition.toFloat(), true)
# Menjadi:
#     if (isTouchScreenVisible()) {
#         NativeLibrary.onTouchEvent(xPosition.toFloat(), yPosition.toFloat(), true)
#     }
# ============================================================
echo ""
echo "=== Step 5: Guard NativeLibrary.onTouchEvent (ACTION_DOWN) ==="

python3 - "$FILE" << 'PYEOF'
import sys
import re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Pattern: onTouchEvent dengan xPosition, yPosition, true (bukan 0f, false)
pattern = r'(\s+)(NativeLibrary\.onTouchEvent\(xPosition\.toFloat\(\), yPosition\.toFloat\(\), true\))'

already_guarded = "isTouchScreenVisible()" in content and \
    re.search(r'isTouchScreenVisible\(\).*\n.*NativeLibrary\.onTouchEvent\(xPosition', content, re.DOTALL)

if already_guarded:
    print("Guard onTouchEvent (ACTION_DOWN) sudah ada, skip.")
else:
    def replacer(m):
        indent = m.group(1)
        call = m.group(2).strip()
        return f"{indent}if (isTouchScreenVisible()) {{\n{indent}    {call}\n{indent}}}"
    
    new_content = re.sub(pattern, replacer, content)
    if new_content != content:
        content = new_content
        print("Guard onTouchEvent (ACTION_DOWN) berhasil ditambahkan.")
    else:
        print("WARNING: Pattern onTouchEvent(xPosition, yPosition, true) tidak ditemukan.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 6: Guard onTouchEvent untuk ACTION_UP / release
# Pattern: NativeLibrary.onTouchEvent(0f, false) — ini release,
# juga harus di-guard supaya tidak mengirim release ke layar
# yang tidak pernah menerima press.
# ============================================================
echo ""
echo "=== Step 6: Guard NativeLibrary.onTouchEvent (ACTION_UP/release) ==="

python3 - "$FILE" << 'PYEOF'
import sys
import re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Pattern release: onTouchEvent(0f, 0f, false) atau onTouchEvent(Of, false)
# Dari screenshot terlihat: NativeLibrary.onTouchEvent(Of, false)
pattern = r'(\s+)(NativeLibrary\.onTouchEvent\(0f,\s*0f,\s*false\)|NativeLibrary\.onTouchEvent\(0f,\s*false\)|NativeLibrary\.onTouchEvent\(Of,\s*false\))'

def replacer(m):
    indent = m.group(1)
    call = m.group(2).strip()
    return f"{indent}if (isTouchScreenVisible()) {{\n{indent}    {call}\n{indent}}}"

new_content = re.sub(pattern, replacer, content)
if new_content != content:
    content = new_content
    print("Guard onTouchEvent (release) berhasil ditambahkan.")
else:
    print("INFO: Pattern onTouchEvent release tidak ditemukan atau sudah di-guard.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Verifikasi hasil
# ============================================================
echo ""
echo "=== Verifikasi hasil ==="
echo "--- Import yang ditambahkan ---"
grep -n "IntSetting\|ScreenLayout" "$FILE" | head -5

echo ""
echo "--- Helper function ---"
grep -n "isTouchScreenVisible\|SINGLE_SCREEN" "$FILE"

echo ""
echo "--- Guard di onTouchMoved ---"
grep -n -A2 "isTouchScreenVisible" "$FILE" | head -30

echo ""
echo "=== SELESAI ==="
echo "File yang dimodifikasi: $FILE"
echo "Backup ada di: ${FILE}.bak"
echo ""
echo "Selanjutnya: git add && git commit && git push"
