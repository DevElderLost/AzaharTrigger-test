#!/bin/bash
# =============================================================================
# fix_mainactivity_menu_type.sh  — surgical fix baris 599-601
# Ganti nullable chain .menu?.findItem().let dengan explicit typed approach
# =============================================================================

set -e
REPO_ROOT="${1:-.}"
MAIN="$REPO_ROOT/src/android/app/src/main/java/org/citra/citra_emu/ui/main/MainActivity.kt"

[ -f "$MAIN" ] || { echo "[ERROR] Tidak ditemukan: $MAIN"; exit 1; }

mkdir -p /tmp/bak_bootmenu_azahar
cp "$MAIN" "/tmp/bak_bootmenu_azahar/MainActivity.kt.bak_menutype"

python3 - "$MAIN" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# ── Fix 1: refreshAndUpdateHomeMenuNav — ganti nullable chain yang error ──────
# Yang error:
#   binding.navigationView?.menu?.findItem(R.id.bootHomeMenu)?.let {
#       it.isVisible = available
#       it.isEnabled = available
#   }
# Fix: cast explicit NavigationBarView, akses menu langsung

OLD_REFRESH = '''    private fun refreshAndUpdateHomeMenuNav() {
        homeViewModel.refreshHomeMenuAvailability()
        val (available, _) = homeViewModel.homeMenuAvailable.value
        binding.navigationView?.menu?.findItem(R.id.bootHomeMenu)?.let {
            it.isVisible = available
            it.isEnabled = available
        }
    }'''

NEW_REFRESH = '''    private fun refreshAndUpdateHomeMenuNav() {
        homeViewModel.refreshHomeMenuAvailability()
        val (available, _) = homeViewModel.homeMenuAvailable.value
        val navView = binding.navigationView ?: return
        val bootItem = navView.menu.findItem(R.id.bootHomeMenu) ?: return
        bootItem.isVisible = available
        bootItem.isEnabled = available
    }'''

if OLD_REFRESH in content:
    content = content.replace(OLD_REFRESH, NEW_REFRESH)
    print("    [OK] refreshAndUpdateHomeMenuNav() diperbaiki (explicit non-nullable)")
else:
    # Coba pola yang lebih fleksibel — cari baris spesifik yang error
    import re
    # Ganti pattern nullable chain
    pattern = r'(binding\.navigationView\?\.menu\?\.findItem\(R\.id\.bootHomeMenu\)\?\.let \{[^}]*\})'
    replacement = '''val navView = binding.navigationView ?: return
        val bootItem = navView.menu.findItem(R.id.bootHomeMenu) ?: return
        bootItem.isVisible = available
        bootItem.isEnabled = available'''
    new_content, count = re.subn(pattern, replacement, content, flags=re.DOTALL)
    if count > 0:
        content = new_content
        print(f"    [OK] Nullable chain diperbaiki via regex ({count} penggantian)")
    else:
        print("    [WARN] Pattern tidak ditemukan — cari manual di refreshAndUpdateHomeMenuNav()")
        # Dump baris sekitar error untuk debug
        lines = content.split('\n')
        for i, line in enumerate(lines):
            if 'bootHomeMenu' in line and ('menu' in line or 'isVisible' in line or 'isEnabled' in line):
                start = max(0, i-2)
                end = min(len(lines), i+5)
                print(f"    Baris {start+1}-{end}:")
                for j in range(start, end):
                    print(f"      {j+1}: {lines[j]}")

with open(path, 'w') as f:
    f.write(content)

print("    Fix selesai!")
PYEOF

echo ""
echo " Jalankan sekarang:"
echo "   git add -A && git commit -m 'fix: menu item type error in refreshAndUpdateHomeMenuNav'"
echo ""
