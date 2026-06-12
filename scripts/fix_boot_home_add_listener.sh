#!/bin/bash
# fix_boot_home_add_listener.sh
# Tambah addOnItemSelectedListener untuk handle bootHomeMenu
# karena MainActivity pakai NavigationUI.setupWithNavController
# tanpa setOnItemSelectedListener manual

set -e
REPO_ROOT="${1:-.}"
MAIN="$REPO_ROOT/src/android/app/src/main/java/org/citra/citra_emu/ui/main/MainActivity.kt"

[ -f "$MAIN" ] || { echo "[ERROR] $MAIN tidak ditemukan"; exit 1; }

mkdir -p /tmp/bak_bootmenu_azahar
cp "$MAIN" "/tmp/bak_bootmenu_azahar/MainActivity.kt.bak_addlistener"

python3 - "$MAIN" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# ── Cari anchor: setOnItemReselectedListener { ────────────────────────────
# Kita sisipkan addOnItemSelectedListener SETELAH closing } dari
# setOnItemReselectedListener block

TARGET = '.setOnItemReselectedListener {'

idx = content.find(TARGET)
if idx == -1:
    print("[ERROR] setOnItemReselectedListener tidak ditemukan!")
    sys.exit(1)

# Hitung brace balance untuk cari penutup block
brace_start = content.find('{', idx)
depth = 0
pos = brace_start
block_end = -1
while pos < len(content):
    if content[pos] == '{':
        depth += 1
    elif content[pos] == '}':
        depth -= 1
        if depth == 0:
            block_end = pos
            break
    pos += 1

if block_end == -1:
    print("[ERROR] Tidak bisa menemukan penutup setOnItemReselectedListener!")
    sys.exit(1)

print(f"    setOnItemReselectedListener block: pos {idx} - {block_end}")

# Cek apakah addOnItemSelectedListener untuk bootHomeMenu sudah ada
if 'addOnItemSelectedListener' in content[idx:block_end+200] and 'bootHomeMenu' in content[idx:block_end+500]:
    print("    [INFO] addOnItemSelectedListener bootHomeMenu sudah ada, skip")
else:
    # Sisipkan setelah } penutup setOnItemReselectedListener
    # Cari akhir baris dari block_end
    after_block = block_end + 1
    # Skip whitespace/newline sebentar untuk cari posisi yang bersih
    eol = content.find('\n', block_end)
    
    new_listener = '''

        // ── Boot HOME Menu: handle via addOnItemSelectedListener ────────────
        // NavigationUI.setupWithNavController tidak bisa handle item yang bukan
        // fragment destination, jadi kita intercept di sini
        (binding.navigationView as NavigationBarView).addOnItemSelectedListener { item ->
            if (item.itemId == R.id.bootHomeMenu) {
                launchBootHomeMenu()
                true
            } else {
                false
            }
        }'''
    
    content = content[:eol] + new_listener + content[eol:]
    print("    [OK] addOnItemSelectedListener untuk bootHomeMenu ditambahkan")

# ── Pastikan import NavigationBarView ada ────────────────────────────────
imp = 'import com.google.android.material.navigation.NavigationBarView'
if imp not in content:
    idx_imp = content.find('\nimport ')
    if idx_imp != -1:
        content = content[:idx_imp] + '\n' + imp + content[idx_imp:]
        print("    [OK] Import NavigationBarView ditambahkan")

# ── Verifikasi launchBootHomeMenu ada ────────────────────────────────────
if 'fun launchBootHomeMenu' not in content:
    print("    [WARN] launchBootHomeMenu() tidak ditemukan! Pastikan sudah ada di file.")
else:
    print("    [OK] launchBootHomeMenu() tersedia")

with open(path, 'w') as f:
    f.write(content)

print("    Selesai!")
PYEOF

echo ""
echo "================================================================"
echo " Fix selesai!"
echo "================================================================"
echo ""
echo " Jalankan:"
echo "   git add -A && git commit -m 'fix: add boot home menu nav listener'"
echo ""
