#!/bin/bash
# fix_launch_boot_home_correct.sh
# Perbaiki launchBootHomeMenu() agar identik dengan tombol Start
# di SystemFilesFragment (baris 377-385)
#
# Cara kerja Start yang benar:
#   1. homeMenuMap = Map<regionString, path> dari NativeLibrary.getHomeMenuPath(region)
#   2. filter homeMenuMap yang value != ""
#   3. ambil path dari map, buat Game(), navigate via actionGlobalEmulationActivity
#
# HomeViewModel.homeMenuAvailable sudah menyimpan path pertama yang tersedia
# Jadi launchBootHomeMenu() cukup pakai path itu

set -e
REPO_ROOT="${1:-.}"
MAIN="$REPO_ROOT/src/android/app/src/main/java/org/citra/citra_emu/ui/main/MainActivity.kt"

[ -f "$MAIN" ] || { echo "[ERROR] $MAIN tidak ditemukan"; exit 1; }

mkdir -p /tmp/bak_bootmenu_azahar
cp "$MAIN" "/tmp/bak_bootmenu_azahar/MainActivity.kt.bak_launchfix"

python3 - "$MAIN" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# ── STEP 1: Ganti launchBootHomeMenu() dengan implementasi yang benar ─────
# Cari fungsi lama dan hapus seluruhnya

# Temukan fungsi launchBootHomeMenu
old_func_start = content.find('    fun launchBootHomeMenu()')
if old_func_start == -1:
    old_func_start = content.find('    private fun launchBootHomeMenu()')

if old_func_start != -1:
    # Cari brace pembuka
    brace_open = content.find('{', old_func_start)
    # Hitung brace balance untuk cari penutup
    depth = 0
    pos = brace_open
    func_end = -1
    while pos < len(content):
        if content[pos] == '{':
            depth += 1
        elif content[pos] == '}':
            depth -= 1
            if depth == 0:
                func_end = pos
                break
        pos += 1
    
    if func_end != -1:
        # Hapus fungsi lama (termasuk komentar di atasnya jika ada)
        # Cek apakah ada komentar sebelum fungsi
        chunk_before = content[max(0, old_func_start-200):old_func_start]
        comment_start = old_func_start
        # Cari baris komentar tepat sebelum fungsi
        lines_before = content[:old_func_start].split('\n')
        # Hapus baris kosong dan komentar di akhir
        trim_idx = old_func_start
        temp = content[:old_func_start].rstrip()
        if temp.endswith('*/') or temp.endswith('//'):
            # ada komentar, cari awalnya
            last_newline = temp.rfind('\n')
            if last_newline != -1:
                trim_idx = last_newline + 1

        old_func = content[trim_idx:func_end+1]
        
        # Fungsi baru yang benar — identik dengan SystemFilesFragment
        new_func = '''    fun launchBootHomeMenu() {
        // Identik dengan tombol Start di SystemFilesFragment
        // homeMenuAvailable.value.second = path dari NativeLibrary.getHomeMenuPath(region)
        val menuPath = homeViewModel.homeMenuAvailable.value.second
        if (menuPath.isEmpty()) {
            Snackbar.make(
                binding.root,
                R.string.boot_home_menu_no_system,
                Snackbar.LENGTH_LONG
            ).show()
            return
        }
        val menu = Game(
            title = getString(R.string.home_menu),
            path = menuPath,
            filename = ""
        )
        val action = HomeNavigationDirections.actionGlobalEmulationActivity(menu)
        binding.root.findNavController().navigate(action)
    }'''
        
        content = content[:trim_idx] + new_func + content[func_end+1:]
        print("    [OK] launchBootHomeMenu() diganti dengan implementasi yang benar")
    else:
        print("    [WARN] Tidak bisa menemukan penutup launchBootHomeMenu()")
else:
    # Fungsi belum ada — tambahkan sebelum } terakhir
    print("    [INFO] launchBootHomeMenu() belum ada, menambahkan...")
    new_func = '''
    fun launchBootHomeMenu() {
        val menuPath = homeViewModel.homeMenuAvailable.value.second
        if (menuPath.isEmpty()) {
            Snackbar.make(
                binding.root,
                R.string.boot_home_menu_no_system,
                Snackbar.LENGTH_LONG
            ).show()
            return
        }
        val menu = Game(
            title = getString(R.string.home_menu),
            path = menuPath,
            filename = ""
        )
        val action = HomeNavigationDirections.actionGlobalEmulationActivity(menu)
        binding.root.findNavController().navigate(action)
    }
'''
    last_brace = content.rfind('\n}')
    if last_brace != -1:
        content = content[:last_brace] + new_func + content[last_brace:]

# ── STEP 2: Pastikan import findNavController tersedia ────────────────────
nav_imports = [
    'import androidx.navigation.findNavController',
    'import org.citra.citra_emu.model.Game',
    'import org.citra.citra_emu.HomeNavigationDirections',
    'import com.google.android.material.snackbar.Snackbar',
]
for imp in nav_imports:
    if imp not in content:
        idx = content.find('\nimport ')
        if idx != -1:
            content = content[:idx] + '\n' + imp + content[idx:]
            print(f"    [OK] Import ditambahkan: {imp.split('.')[-1]}")

# ── STEP 3: Pastikan addOnItemSelectedListener sudah ada ─────────────────
if 'addOnItemSelectedListener' not in content:
    print("    [WARN] addOnItemSelectedListener belum ada!")
    print("           Jalankan fix_boot_home_add_listener.sh terlebih dahulu")
else:
    print("    [OK] addOnItemSelectedListener sudah ada")

# ── STEP 4: Pastikan refreshHomeMenuAvailability dipanggil di onResume/onStart
if 'refreshHomeMenuAvailability' not in content:
    print("    [WARN] refreshHomeMenuAvailability tidak dipanggil di MainActivity")
    # Tambah di onResume
    on_resume = content.find('override fun onResume()')
    if on_resume != -1:
        brace = content.find('{', on_resume)
        eol = content.find('\n', brace)
        content = content[:eol] + '\n        homeViewModel.refreshHomeMenuAvailability()' + content[eol:]
        print("    [OK] refreshHomeMenuAvailability() ditambahkan di onResume()")
else:
    print("    [OK] refreshHomeMenuAvailability sudah dipanggil")

with open(path, 'w') as f:
    f.write(content)

print("")
print("    Verifikasi launchBootHomeMenu:")
# Print fungsi hasil
idx_verify = content.find('fun launchBootHomeMenu()')
if idx_verify != -1:
    print(content[idx_verify:idx_verify+400])

print("    Selesai!")
PYEOF

echo ""
echo "================================================================"
echo " Fix selesai!"
echo "================================================================"
echo ""
echo " Jalankan:"
echo "   git add -A && git commit -m 'fix: correct launchBootHomeMenu implementation'"
echo ""
