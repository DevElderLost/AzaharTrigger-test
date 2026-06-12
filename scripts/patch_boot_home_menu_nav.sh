#!/bin/bash
# =============================================================================
# patch_boot_home_menu_nav.sh  (v2 — fixed paths)
# AzaharTrigger-test — Tambah bottom navigation "Boot HOME Menu"
# =============================================================================

set -e
REPO_ROOT="${1:-.}"

ANDROID_RES="$REPO_ROOT/src/android/app/src/main/res"
ANDROID_JAVA="$REPO_ROOT/src/android/app/src/main/java/org/citra/citra_emu"

echo "=== [AzaharTrigger] Patch: Boot HOME Menu bottom navigation ==="
echo "    Repo root: $REPO_ROOT"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
require_file() {
    if [ ! -f "$1" ]; then
        echo "[ERROR] File tidak ditemukan: $1"
        exit 1
    fi
}

backup_file() {
    cp "$1" "$1.bak_bootmenu" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Lokasi file — path sudah diverifikasi dari repo
# ---------------------------------------------------------------------------
MENU_NAV_XML="$ANDROID_RES/menu/menu_navigation.xml"
HOME_NAV_XML="$ANDROID_RES/navigation/home_navigation.xml"
STRINGS_XML="$ANDROID_RES/values/strings.xml"
DRAWABLES_DIR="$ANDROID_RES/drawable"
HOME_VM="$ANDROID_JAVA/viewmodel/HomeViewModel.kt"
MAIN_ACTIVITY="$ANDROID_JAVA/ui/main/MainActivity.kt"
GAMES_FRAGMENT="$ANDROID_JAVA/fragments/GamesFragment.kt"

# ---------------------------------------------------------------------------
# Validasi
# ---------------------------------------------------------------------------
require_file "$MENU_NAV_XML"
require_file "$STRINGS_XML"
require_file "$HOME_NAV_XML"

echo ""
echo "    Semua file target ditemukan. Mulai patch..."

# ---------------------------------------------------------------------------
# PATCH 1: menu/menu_navigation.xml — tambah item "Boot HOME Menu"
# ---------------------------------------------------------------------------
echo ""
echo "[1/5] Patching menu_navigation.xml ..."
backup_file "$MENU_NAV_XML"

if grep -q "bootHomeMenu" "$MENU_NAV_XML"; then
    echo "      Sudah di-patch, skip."
else
python3 - "$MENU_NAV_XML" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

new_item = '''
    <item
        android:id="@+id/bootHomeMenu"
        android:icon="@drawable/ic_boot_home_menu"
        android:title="@string/boot_home_menu_nav" />'''

# Sisipkan setelah </item> pertama (item "home" / "gamesFragment")
first_end = content.find('</item>')
if first_end != -1:
    pos = first_end + len('</item>')
    content = content[:pos] + new_item + content[pos:]
else:
    content = content.replace('</menu>', new_item + '\n</menu>')

with open(path, 'w') as f:
    f.write(content)

print("      menu_navigation.xml patched OK")
PYEOF
fi

# ---------------------------------------------------------------------------
# PATCH 2: Buat drawable ic_boot_home_menu.xml
# ---------------------------------------------------------------------------
echo ""
echo "[2/5] Membuat drawable ic_boot_home_menu.xml ..."
ICON_FILE="$DRAWABLES_DIR/ic_boot_home_menu.xml"

if [ -f "$ICON_FILE" ]; then
    echo "      Icon sudah ada, skip."
else
    cat > "$ICON_FILE" << 'ICONEOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24"
    android:tint="?attr/colorControlNormal">
  <!-- House shape -->
  <path
      android:fillColor="@android:color/white"
      android:pathData="M10,20v-6h4v6h5v-8h3L12,3 2,12h3v8z"/>
  <!-- Small play triangle overlay bottom-right -->
  <path
      android:fillColor="@android:color/white"
      android:pathData="M15,14l4,2.5 -4,2.5z"/>
</vector>
ICONEOF
    echo "      ic_boot_home_menu.xml dibuat."
fi

# ---------------------------------------------------------------------------
# PATCH 3: strings.xml — tambah string baru
# ---------------------------------------------------------------------------
echo ""
echo "[3/5] Patching strings.xml ..."
backup_file "$STRINGS_XML"

if grep -q "boot_home_menu_nav" "$STRINGS_XML"; then
    echo "      String sudah ada, skip."
else
python3 - "$STRINGS_XML" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

new_strings = '''
    <!-- Boot HOME Menu navigation -->
    <string name="boot_home_menu_nav">HOME</string>
    <string name="boot_home_menu_no_system">No HOME Menu installed. Set up System Files first.</string>
'''
content = content.replace('</resources>', new_strings + '</resources>')

with open(path, 'w') as f:
    f.write(content)

print("      strings.xml patched OK")
PYEOF
fi

# ---------------------------------------------------------------------------
# PATCH 4: HomeViewModel.kt — tambah homeMenuAvailable + refresh function
# ---------------------------------------------------------------------------
echo ""
echo "[4/5] Patching HomeViewModel.kt ..."

if [ ! -f "$HOME_VM" ]; then
    echo "      [WARN] HomeViewModel.kt tidak ditemukan di: $HOME_VM"
    echo "             Cari manual:"
    find "$REPO_ROOT/src/android" -name "HomeViewModel.kt" 2>/dev/null | head -5
    SKIP_VM=1
else
    SKIP_VM=0
fi

if [ "$SKIP_VM" = "0" ]; then
    backup_file "$HOME_VM"

    if grep -q "homeMenuAvailable" "$HOME_VM"; then
        echo "      Sudah di-patch, skip."
    else
python3 - "$HOME_VM" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Tambah import jika belum ada
new_imports = [
    'import org.citra.citra_emu.NativeLibrary',
    'import kotlinx.coroutines.flow.MutableStateFlow',
    'import kotlinx.coroutines.flow.StateFlow',
    'import kotlinx.coroutines.flow.asStateFlow',
]
for imp in new_imports:
    if imp not in content:
        idx = content.find('\nimport ')
        if idx != -1:
            content = content[:idx] + '\n' + imp + content[idx:]

# Sisipkan field + fungsi setelah buka kurung class
class_match = re.search(r'class HomeViewModel[^{]*\{', content)
if class_match:
    pos = class_match.end()
    new_code = '''

    // ── Boot HOME Menu availability ──────────────────────────────────
    private val _homeMenuAvailable = MutableStateFlow(Pair(false, ""))
    val homeMenuAvailable: StateFlow<Pair<Boolean, String>> = _homeMenuAvailable.asStateFlow()

    fun refreshHomeMenuAvailability() {
        val firstPath = (0..6)
            .map { NativeLibrary.getHomeMenuPath(it) }
            .firstOrNull { it.isNotEmpty() }
        _homeMenuAvailable.value = if (firstPath != null) Pair(true, firstPath)
                                   else Pair(false, "")
    }
'''
    content = content[:pos] + new_code + content[pos:]

with open(path, 'w') as f:
    f.write(content)

print("      HomeViewModel.kt patched OK")
PYEOF
    fi
fi

# ---------------------------------------------------------------------------
# PATCH 5: MainActivity.kt — observer + click handler
# ---------------------------------------------------------------------------
echo ""
echo "[5/5] Patching MainActivity.kt ..."

if [ ! -f "$MAIN_ACTIVITY" ]; then
    echo "      [WARN] MainActivity.kt tidak ditemukan di: $MAIN_ACTIVITY"
    echo "             Cari manual:"
    find "$REPO_ROOT/src/android" -name "MainActivity.kt" 2>/dev/null | head -5
    SKIP_MAIN=1
else
    SKIP_MAIN=0
fi

if [ "$SKIP_MAIN" = "0" ]; then
    backup_file "$MAIN_ACTIVITY"

    if grep -q "bootHomeMenu" "$MAIN_ACTIVITY"; then
        echo "      Sudah di-patch, skip."
    else
python3 - "$MAIN_ACTIVITY" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Tambah import
new_imports = [
    'import androidx.lifecycle.Lifecycle',
    'import androidx.lifecycle.lifecycleScope',
    'import androidx.lifecycle.repeatOnLifecycle',
    'import kotlinx.coroutines.launch',
    'import org.citra.citra_emu.HomeNavigationDirections',
    'import org.citra.citra_emu.model.Game',
    'import com.google.android.material.snackbar.Snackbar',
]
for imp in new_imports:
    if imp not in content:
        idx = content.find('\nimport ')
        if idx != -1:
            content = content[:idx] + '\n' + imp + content[idx:]

# Sisipkan pemanggilan setupBootHomeMenuNav() setelah setupNavigation() atau setContentView
CALL_CODE = '\n        setupBootHomeMenuNav()'
anchors = ['setupNavigation()', 'setupObservers()', 'setContentView(binding.root)', 'setContentView(']
for anchor in anchors:
    idx = content.find(anchor)
    if idx != -1:
        eol = content.find('\n', idx)
        if eol != -1 and 'setupBootHomeMenuNav' not in content[idx:idx+300]:
            content = content[:eol] + CALL_CODE + content[eol:]
            print(f"      Inserted call after '{anchor}'")
            break

# Tambah fungsi setupBootHomeMenuNav + launchBootHomeMenu sebelum } terakhir
NEW_FUNCS = '''
    // ── Boot HOME Menu navigation ──────────────────────────────────────────
    private fun setupBootHomeMenuNav() {
        homeViewModel.refreshHomeMenuAvailability()

        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                homeViewModel.homeMenuAvailable.collect { (available, _) ->
                    binding.navigationView?.menu
                        ?.findItem(R.id.bootHomeMenu)
                        ?.let { item ->
                            item.isVisible = available
                            item.isEnabled = available
                        }
                }
            }
        }

        binding.navigationView?.setOnItemSelectedListener { item ->
            when (item.itemId) {
                R.id.bootHomeMenu -> { launchBootHomeMenu(); true }
                else -> false
            }
        }
    }

    fun launchBootHomeMenu() {
        val (available, menuPath) = homeViewModel.homeMenuAvailable.value
        if (!available || menuPath.isEmpty()) {
            Snackbar.make(binding.root, R.string.boot_home_menu_no_system,
                          Snackbar.LENGTH_LONG).show()
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
    content = content[:last_brace] + NEW_FUNCS + content[last_brace:]

with open(path, 'w') as f:
    f.write(content)

print("      MainActivity.kt patched OK")
PYEOF
    fi
fi

# ---------------------------------------------------------------------------
# PATCH BONUS: GamesFragment.kt — refresh saat onStart
# ---------------------------------------------------------------------------
if [ -f "$GAMES_FRAGMENT" ]; then
    echo ""
    echo "[BONUS] Patching GamesFragment.kt ..."
    backup_file "$GAMES_FRAGMENT"

    if grep -q "refreshHomeMenuAvailability" "$GAMES_FRAGMENT"; then
        echo "        Sudah di-patch, skip."
    else
python3 - "$GAMES_FRAGMENT" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

REFRESH = '\n        homeViewModel.refreshHomeMenuAvailability()'
for hook in ['override fun onStart()', 'override fun onResume()']:
    idx = content.find(hook)
    if idx != -1:
        brace = content.find('{', idx)
        eol = content.find('\n', brace)
        if eol != -1 and 'refreshHomeMenuAvailability' not in content[brace:brace+200]:
            content = content[:eol] + REFRESH + content[eol:]
            print(f"        Added refresh in {hook}")
        break

with open(path, 'w') as f:
    f.write(content)
PYEOF
    fi
fi

# ---------------------------------------------------------------------------
# Selesai
# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo " PATCH SELESAI!"
echo "================================================================"
echo ""
echo " File dimodifikasi:"
echo "   * res/menu/menu_navigation.xml     — item bootHomeMenu ditambahkan"
echo "   * res/drawable/ic_boot_home_menu.xml"
echo "   * res/values/strings.xml"
echo "   * viewmodel/HomeViewModel.kt"
[ "$SKIP_MAIN" = "0" ] && echo "   * ui/main/MainActivity.kt"
[ -f "$GAMES_FRAGMENT" ] && echo "   * fragments/GamesFragment.kt"
echo ""
echo " CATATAN:"
echo "   - Pastikan binding.navigationView sesuai ID di layout MainActivity"
echo "   - Jika sudah ada setOnItemSelectedListener, gabungkan manual"
echo "   - Backup tersedia di file *.bak_bootmenu"
echo ""
