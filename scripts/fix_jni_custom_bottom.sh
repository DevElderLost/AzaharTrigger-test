#!/usr/bin/env bash
# Fix: Tambah JNI function SetCustomBottomScreen di native.cpp + NativeLibrary.kt
# dan update InputOverlay.kt untuk pakai JNI call bukan IntSetting

set -euo pipefail
REPO_ROOT="${1:-.}"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
die()  { echo -e "${RED}[ERR]${NC}  $*" >&2; exit 1; }

find_file() { find "$REPO_ROOT" -type f -path "*$1" 2>/dev/null | head -1; }
require_file() {
    local f; f=$(find_file "$1")
    [[ -n "$f" && -f "$f" ]] || die "File tidak ditemukan: *$1"
    echo "$f"
}

echo ""
echo "══════════════════════════════════════════════"
echo "  Fix: Add JNI SetCustomBottomScreen"
echo "══════════════════════════════════════════════"

# =============================================================================
# 1. native.cpp — tambah JNI function SetCustomBottomScreen
# =============================================================================
echo ""
echo "━━ [1/3] native.cpp"

NATIVE_CPP=$(require_file "jni/native.cpp")

if grep -q "SetCustomBottomScreen" "$NATIVE_CPP"; then
    info "SetCustomBottomScreen sudah ada — skip"
else
    python3 - "$NATIVE_CPP" << 'PYEOF'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
content = f.read_text(encoding='utf-8')

# Cari fungsi UpdateFramebuffer sebagai anchor — sisipkan sebelumnya
ANCHOR = 'void Java_org_citra_citra_emu_NativeLibrary_updateFramebuffer([[maybe_unused]] JNIEnv* env,'
if ANCHOR not in content:
    print("ERROR: anchor UpdateFramebuffer tidak ditemukan")
    sys.exit(1)

NEW_FUNC = '''\
void Java_org_citra_citra_emu_NativeLibrary_GetCustomTopScreen(
    JNIEnv* env, [[maybe_unused]] jclass clazz, jintArray out) {
    jint vals[4] = {
        static_cast<jint>(Settings::values.custom_top_x.GetValue()),
        static_cast<jint>(Settings::values.custom_top_y.GetValue()),
        static_cast<jint>(Settings::values.custom_top_width.GetValue()),
        static_cast<jint>(Settings::values.custom_top_height.GetValue())
    };
    env->SetIntArrayRegion(out, 0, 4, vals);
}

void Java_org_citra_citra_emu_NativeLibrary_GetCustomBottomScreen(
    JNIEnv* env, [[maybe_unused]] jclass clazz, jintArray out) {
    jint vals[4] = {
        static_cast<jint>(Settings::values.custom_bottom_x.GetValue()),
        static_cast<jint>(Settings::values.custom_bottom_y.GetValue()),
        static_cast<jint>(Settings::values.custom_bottom_width.GetValue()),
        static_cast<jint>(Settings::values.custom_bottom_height.GetValue())
    };
    env->SetIntArrayRegion(out, 0, 4, vals);
}

void Java_org_citra_citra_emu_NativeLibrary_SetCustomBottomScreen(
    [[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz,
    jint x, jint y, jint width, jint height) {
    Settings::values.custom_bottom_x  = static_cast<u16>(x);
    Settings::values.custom_bottom_y  = static_cast<u16>(y);
    Settings::values.custom_bottom_width  = static_cast<u16>(width);
    Settings::values.custom_bottom_height = static_cast<u16>(height);
    // Langsung update framebuffer setelah set koordinat
    if (system_) {
        system_->GPU().Renderer().UpdateCurrentFramebufferLayout(IsPortraitMode());
    }
}

'''
new_content = content.replace(ANCHOR, NEW_FUNC + ANCHOR, 1)
f.write_text(new_content, encoding='utf-8')
print(f"  [PATCHED] {f.name}")
PYEOF
fi
ok "native.cpp"

# =============================================================================
# 2. NativeLibrary.kt — tambah external fun declaration
# =============================================================================
echo ""
echo "━━ [2/3] NativeLibrary.kt"

NATIVE_LIB=$(require_file "NativeLibrary.kt")

if grep -q "SetCustomBottomScreen" "$NATIVE_LIB"; then
    info "Deklarasi sudah ada — skip"
else
    python3 - "$NATIVE_LIB" << 'PYEOF'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
content = f.read_text(encoding='utf-8')

ANCHOR = 'external fun updateFramebuffer(isPortrait: Boolean)'
if ANCHOR not in content:
    # coba variasi
    import re
    m = re.search(r'external fun updateFramebuffer[^\n]*', content)
    if m:
        ANCHOR = m.group(0)
        print(f"  Found anchor: {ANCHOR}")
    else:
        print("ERROR: anchor updateFramebuffer tidak ditemukan")
        sys.exit(1)

NEW_DECLS = '''\
external fun updateFramebuffer(isPortrait: Boolean)

        // Custom layout bottom screen direct C++ access
        @JvmStatic external fun setCustomBottomScreen(x: Int, y: Int, width: Int, height: Int)
        @JvmStatic external fun getCustomBottomScreen(): IntArray'''

content = content.replace(ANCHOR,
    'external fun updateFramebuffer(isPortrait: Boolean)\n\n        // Custom layout bottom screen direct C++ access\n        @JvmStatic external fun setCustomBottomScreen(x: Int, y: Int, width: Int, height: Int)\n        @JvmStatic external fun getCustomBottomScreen(): IntArray',
    1)
f.write_text(content, encoding='utf-8')
print(f"  [PATCHED] {f.name}")
PYEOF
fi
ok "NativeLibrary.kt"

# =============================================================================
# 3. InputOverlay.kt — ganti IntSetting calls dengan NativeLibrary JNI calls
# =============================================================================
echo ""
echo "━━ [3/3] InputOverlay.kt"

OVERLAY=$(require_file "overlay/InputOverlay.kt")

python3 - "$OVERLAY" << 'PYEOF'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
lines = f.read_text(encoding='utf-8').splitlines(keepends=True)

start_idx = None
end_idx = None
for i, line in enumerate(lines):
    if 'private fun toggleHideSecondaryScreen' in line:
        start_idx = i
    if start_idx and i > start_idx and 'fun hapticFeedback' in line:
        end_idx = i
        break

if start_idx is None or end_idx is None:
    print(f"ERROR: fungsi tidak ditemukan start={start_idx} end={end_idx}")
    sys.exit(1)

NEW_FUNC = '''\
    private fun toggleHideSecondaryScreen() {
        val isPortrait = NativeLibrary.isPortraitMode
        val isHidden = preferences.getBoolean("secondaryScreenHidden", false)

        if (!isHidden) {
            // ── Sembunyikan secondary screen ─────────────────────────────────
            // 1. Backup posisi bottom screen dari C++ langsung
            val current = NativeLibrary.getCustomBottomScreen()
            preferences.edit()
                .putInt("backup_bottom_x",      current[0])
                .putInt("backup_bottom_y",      current[1])
                .putInt("backup_bottom_width",  current[2])
                .putInt("backup_bottom_height", current[3])
                .putBoolean("secondaryScreenHidden", true)
                .apply()

            // 2. Ambil koordinat top screen, set bottom = top → tertutup di belakang top
            val top = NativeLibrary.getCustomTopScreen()
            NativeLibrary.setCustomBottomScreen(top[0], top[1], top[2], top[3])
        } else {
            // ── Tampilkan kembali secondary screen ───────────────────────────
            val bx = preferences.getInt("backup_bottom_x",      0)
            val by = preferences.getInt("backup_bottom_y",      0)
            val bw = preferences.getInt("backup_bottom_width",  160)
            val bh = preferences.getInt("backup_bottom_height", 120)
            NativeLibrary.setCustomBottomScreen(bx, by, bw, bh)

            preferences.edit()
                .putBoolean("secondaryScreenHidden", false)
                .remove("backup_bottom_x")
                .remove("backup_bottom_y")
                .remove("backup_bottom_width")
                .remove("backup_bottom_height")
                .apply()
        }

        // Terapkan ke renderer
        NativeLibrary.updateFramebuffer(isPortrait)
    }

'''

new_lines = lines[:start_idx] + [NEW_FUNC] + lines[end_idx:]
f.write_text(''.join(new_lines), encoding='utf-8')
print(f"  [PATCHED] {f.name} (baris {start_idx+1}–{end_idx})")
PYEOF

ok "InputOverlay.kt"

echo ""
echo "══════════════════════════════════════════════"
echo -e "  ${GREEN}Patch selesai!${NC}"
echo "══════════════════════════════════════════════"
echo ""
echo "Commit:"
echo "  git add -A"
echo "  git commit -m 'fix: use JNI for custom bottom screen toggle'"
echo "  git push"
