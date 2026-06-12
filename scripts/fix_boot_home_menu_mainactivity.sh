#!/bin/bash
# =============================================================================
# fix_boot_home_menu_mainactivity.sh
# Fix kompilasi error setelah patch_boot_home_menu_nav.sh
#
# Masalah yang diperbaiki:
#   1. Fungsi setupBootHomeMenuNav() menggunakan API yang salah untuk
#      NavigationBarView (tipe binding.navigationView di MainActivity ini)
#   2. Duplikasi setOnItemSelectedListener — sudah ada di baris ~589
#   3. Unresolved reference: menu, isVisible, isEnabled, findNavController
#
# Strategi fix:
#   - HAPUS fungsi setupBootHomeMenuNav() + launchBootHomeMenu() yang salah
#   - HAPUS pemanggilan setupBootHomeMenuNav() yang disisipkan
#   - SISIPKAN logika bootHomeMenu langsung ke dalam
#     setOnItemSelectedListener yang sudah ada (baris ~589)
#   - Tambah import yang benar
# =============================================================================

set -e
REPO_ROOT="${1:-.}"
MAIN_ACTIVITY="$REPO_ROOT/src/android/app/src/main/java/org/citra/citra_emu/ui/main/MainActivity.kt"

echo "=== [AzaharTrigger] Fix: Boot HOME Menu MainActivity compile errors ==="

if [ ! -f "$MAIN_ACTIVITY" ]; then
    echo "[ERROR] Tidak ditemukan: $MAIN_ACTIVITY"
    exit 1
fi

mkdir -p /tmp/bak_bootmenu_azahar
cp "$MAIN_ACTIVITY" "/tmp/bak_bootmenu_azahar/MainActivity.kt.bak_fix"

python3 - "$MAIN_ACTIVITY" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

print(f"    File size sebelum: {len(content)} chars")

# ============================================================
# STEP 1: Hapus fungsi setupBootHomeMenuNav() yang salah
# ============================================================
# Cari dari komentar penanda sampai akhir fungsi launchBootHomeMenu()
pattern_start = '    // ── Boot HOME Menu navigation ──'
pattern_end_func = '    fun launchBootHomeMenu()'

idx_start = content.find(pattern_start)
if idx_start != -1:
    # Cari penutup fungsi launchBootHomeMenu — cari '}' yang menutup fungsi tsb
    # Cari dari pattern_end_func ke depan, hitung brace balance
    func_start = content.find(pattern_end_func, idx_start)
    if func_start != -1:
        # Cari '{' pembuka fungsi
        brace_open = content.find('{', func_start)
        if brace_open != -1:
            depth = 0
            pos = brace_open
            while pos < len(content):
                if content[pos] == '{':
                    depth += 1
                elif content[pos] == '}':
                    depth -= 1
                    if depth == 0:
                        # +1 untuk include } itu sendiri, +1 untuk newline
                        end_pos = pos + 1
                        # skip trailing newline
                        while end_pos < len(content) and content[end_pos] == '\n':
                            end_pos += 1
                        content = content[:idx_start] + content[end_pos:]
                        print("    [OK] Fungsi setupBootHomeMenuNav + launchBootHomeMenu dihapus")
                        break
                pos += 1
else:
    print("    [INFO] Fungsi setupBootHomeMenuNav tidak ditemukan (mungkin sudah dihapus)")

# ============================================================
# STEP 2: Hapus pemanggilan setupBootHomeMenuNav()
# ============================================================
content = re.sub(r'\n\s*// ── Boot HOME Menu nav button ──[^\n]*\n\s*setupBootHomeMenuNav\(\)', '', content)
content = re.sub(r'\n\s*setupBootHomeMenuNav\(\)', '', content)
print("    [OK] Pemanggilan setupBootHomeMenuNav() dihapus")

# ============================================================
# STEP 3: Tambah import yang dibutuhkan (jika belum ada)
# ============================================================
needed_imports = [
    'import androidx.lifecycle.Lifecycle',
    'import androidx.lifecycle.lifecycleScope',
    'import androidx.lifecycle.repeatOnLifecycle',
    'import kotlinx.coroutines.launch',
    'import org.citra.citra_emu.HomeNavigationDirections',
    'import org.citra.citra_emu.model.Game',
    'import com.google.android.material.snackbar.Snackbar',
    'import androidx.navigation.fragment.NavHostFragment',
]
for imp in needed_imports:
    if imp not in content:
        idx = content.find('\nimport ')
        if idx != -1:
            content = content[:idx] + '\n' + imp + content[idx:]
            print(f"    [OK] Import ditambahkan: {imp.split('.')[-1]}")

# ============================================================
# STEP 4: Sisipkan launchBootHomeMenu() sebagai fungsi terpisah
# (sederhana, tanpa observer — visibility dihandle saat menu dibuat)
# ============================================================
NEW_LAUNCH_FUNC = '''
    // ── Boot HOME Menu — launch langsung (dipanggil dari nav listener) ──────
    fun launchBootHomeMenu() {
        val (available, menuPath) = homeViewModel.homeMenuAvailable.value
        if (!available || menuPath.isEmpty()) {
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
        val navHostFragment = supportFragmentManager
            .findFragmentById(R.id.fragment_container) as? NavHostFragment
        navHostFragment?.navController?.navigate(
            HomeNavigationDirections.actionGlobalEmulationActivity(menu)
        )
    }

    // ── Refresh HOME Menu availability saat activity resume ─────────────────
    private fun refreshAndUpdateHomeMenuNav() {
        homeViewModel.refreshHomeMenuAvailability()
        val (available, _) = homeViewModel.homeMenuAvailable.value
        binding.navigationView?.menu?.findItem(R.id.bootHomeMenu)?.let {
            it.isVisible = available
            it.isEnabled = available
        }
    }
'''

last_brace = content.rfind('\n}')
if last_brace != -1:
    content = content[:last_brace] + NEW_LAUNCH_FUNC + content[last_brace:]
    print("    [OK] launchBootHomeMenu() + refreshAndUpdateHomeMenuNav() ditambahkan")

# ============================================================
# STEP 5: Sisipkan bootHomeMenu case ke dalam setOnItemSelectedListener
#         yang sudah ada di MainActivity (~baris 589)
# ============================================================
# Pola: binding.navigationView?.setOnItemSelectedListener { item ->
listener_pattern = 'binding.navigationView?.setOnItemSelectedListener { item ->'
idx_listener = content.find(listener_pattern)

if idx_listener != -1:
    # Cari baris pertama di dalam lambda — biasanya langsung when atau if
    lambda_body_start = content.find('\n', idx_listener)
    if lambda_body_start != -1:
        # Cek apakah sudah ada bootHomeMenu
        # Cari penutup lambda (brace balance)
        brace_open = content.find('{', idx_listener)
        if brace_open != -1:
            depth = 0
            pos = brace_open
            lambda_end = -1
            while pos < len(content):
                if content[pos] == '{':
                    depth += 1
                elif content[pos] == '}':
                    depth -= 1
                    if depth == 0:
                        lambda_end = pos
                        break
                pos += 1

            lambda_content = content[brace_open:lambda_end+1] if lambda_end != -1 else ""

            if 'bootHomeMenu' in lambda_content:
                print("    [INFO] bootHomeMenu sudah ada di listener, skip")
            else:
                # Sisipkan SEBELUM } penutup lambda
                # Cari 'when' atau langsung tambah di awal body
                when_idx = content.find('when (item.itemId)', idx_listener)
                if when_idx != -1 and when_idx < lambda_end:
                    # Ada when block — sisipkan case baru SEBELUM 'else ->'
                    else_idx = content.find('else ->', when_idx)
                    if else_idx != -1 and else_idx < lambda_end:
                        boot_case = '''                R.id.bootHomeMenu -> {
                    refreshAndUpdateHomeMenuNav()
                    launchBootHomeMenu()
                    true
                }
                '''
                        content = content[:else_idx] + boot_case + content[else_idx:]
                        print("    [OK] Case bootHomeMenu disisipkan ke dalam when() listener")
                    else:
                        print("    [WARN] 'else ->' tidak ditemukan dalam when block")
                else:
                    # Tidak ada when — sisipkan di awal lambda body
                    insert_after = content.find('\n', brace_open)
                    boot_case = '''
                if (item.itemId == R.id.bootHomeMenu) {
                    refreshAndUpdateHomeMenuNav()
                    launchBootHomeMenu()
                    return@setOnItemSelectedListener true
                }
'''
                    content = content[:insert_after] + boot_case + content[insert_after:]
                    print("    [OK] if-block bootHomeMenu disisipkan di awal listener")
else:
    print("    [WARN] setOnItemSelectedListener tidak ditemukan!")
    print("           Tambahkan manual di dalam listener yang ada:")
    print("           R.id.bootHomeMenu -> { refreshAndUpdateHomeMenuNav(); launchBootHomeMenu(); true }")

# ============================================================
# STEP 6: Panggil refreshAndUpdateHomeMenuNav() di onStart/onResume
# ============================================================
for hook in ['override fun onStart()', 'override fun onResume()']:
    idx = content.find(hook)
    if idx != -1:
        brace = content.find('{', idx)
        eol = content.find('\n', brace)
        if eol != -1 and 'refreshAndUpdateHomeMenuNav' not in content[brace:brace+300]:
            content = content[:eol] + '\n        refreshAndUpdateHomeMenuNav()' + content[eol:]
            print(f"    [OK] refreshAndUpdateHomeMenuNav() dipanggil di {hook}")
        break

print(f"    File size sesudah: {len(content)} chars")

with open(path, 'w') as f:
    f.write(content)

print("    MainActivity.kt fix selesai!")
PYEOF

echo ""
echo "================================================================"
echo " FIX SELESAI!"
echo "================================================================"
echo ""
echo " Perubahan:"
echo "   - setupBootHomeMenuNav() (versi lama/salah) dihapus"
echo "   - launchBootHomeMenu() baru ditambahkan (pakai NavHostFragment)"
echo "   - refreshAndUpdateHomeMenuNav() ditambahkan"  
echo "   - bootHomeMenu case disisipkan ke listener yang sudah ada"
echo "   - refreshAndUpdateHomeMenuNav() dipanggil di onStart/onResume"
echo ""
echo " Backup: /tmp/bak_bootmenu_azahar/MainActivity.kt.bak_fix"
echo ""
echo " Sekarang jalankan:"
echo "   git add -A && git commit -m 'fix: boot home menu compile errors'"
echo ""
