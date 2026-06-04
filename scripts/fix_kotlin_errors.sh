#!/bin/bash
# fix_kotlin_errors.sh — Fix 2 error Kotlin ZeroTier
#
# Error 1: ZeroTierDialog pakai android.app.Activity bukan Context
# Error 2: ZeroTierManager referensi ztInit/ztShutdown/ztGetAssignedIP
#          tidak ditemukan karena belum ada di NetPlayManager.kt
#
# Cara pakai:
#   bash scripts/fix_kotlin_errors.sh

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
KOTLIN_BASE="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu"
DIALOGS_DIR="$KOTLIN_BASE/dialogs"
UTILS_DIR="$KOTLIN_BASE/utils"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix Kotlin ZeroTier Errors — AzaharTrigger"
echo "═══════════════════════════════════════════════════════"
echo ""

# ════════════════════════════════════════════════════════════════════
# FIX 1: ZeroTierDialog.kt — ganti Activity dengan Context
# BottomSheetDialog menerima Context, bukan Activity
# ════════════════════════════════════════════════════════════════════
info "Fix 1/2: ZeroTierDialog.kt — ganti Activity dengan Context..."

ZT_DIALOG="$DIALOGS_DIR/ZeroTierDialog.kt"
[ -f "$ZT_DIALOG" ] || error "ZeroTierDialog.kt tidak ditemukan: $ZT_DIALOG"

PATCH_PY=$(mktemp /tmp/fix_kt_XXXXXX.py)
cat > "$PATCH_PY" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Hapus import Activity yang salah
content = content.replace(
    'import android.app.Activity\n', ''
)

# Ganti CompatUtils.findActivity(context) → context
# karena BottomSheetDialog sudah menerima Context langsung
content = content.replace(
    'val activity = CompatUtils.findActivity(context)\n        val dialog = BottomSheetDialog(activity)',
    'val dialog = BottomSheetDialog(context)'
)
content = content.replace(
    'val activity = CompatUtils.findActivity(context)\n',
    ''
)

# Ganti semua sisa referensi activity. → context.
# hanya di dalam ZeroTierDialog (bukan untuk hal lain)
import re

# Ganti activity.getString → context.getString
content = content.replace('activity.getString(', 'context.getString(')
# Ganti activity.resources → context.resources
content = content.replace('activity.resources', 'context.resources')

# Pastikan BottomSheetDialog menerima context bukan activity
content = re.sub(
    r'BottomSheetDialog\(activity\)',
    'BottomSheetDialog(context)',
    content
)

# Hapus import CompatUtils jika tidak dipakai lagi
if 'CompatUtils' not in content or content.count('CompatUtils') == 1:
    content = content.replace(
        'import org.citra.citra_emu.utils.CompatUtils\n', ''
    )

with open(path, 'w') as f:
    f.write(content)
print("  ZeroTierDialog.kt: Activity → Context")
PYEOF

python3 "$PATCH_PY" "$ZT_DIALOG"
rm -f "$PATCH_PY"
success "ZeroTierDialog.kt dipatch"

# ════════════════════════════════════════════════════════════════════
# FIX 2: NetPlayManager.kt — tambah deklarasi ztInit/ztShutdown/ztGetAssignedIP
# Ini yang menyebabkan "Unresolved reference" di ZeroTierManager.kt
# ════════════════════════════════════════════════════════════════════
info "Fix 2/2: NetPlayManager.kt — tambah JNI declarations zt*..."

NETPLAY_MGR=$(find "$PROJECT_ROOT/src" -name "NetPlayManager.kt" | head -1)
[ -n "$NETPLAY_MGR" ] || error "NetPlayManager.kt tidak ditemukan"
info "NetPlayManager.kt: $NETPLAY_MGR"

if ! grep -q "ztInit" "$NETPLAY_MGR"; then
    PATCH_PY2=$(mktemp /tmp/fix_netplay_XXXXXX.py)
    cat > "$PATCH_PY2" << 'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

zt_jni = """
        // ── ZeroTier JNI bridge ──────────────────────────────────────
        // Dipanggil oleh ZeroTierManager untuk kontrol tunnel libzt AAR
        @JvmStatic external fun ztInit(storagePath: String, networkIdHex: String): Int
        @JvmStatic external fun ztShutdown()
        @JvmStatic external fun ztGetAssignedIP(): String
        @JvmStatic external fun ztIsReady(): Boolean
"""

# Sisipkan setelah external fun terakhir yang sudah ada
matches = list(re.finditer(r'@JvmStatic external fun \w+[^\n]*\n', content))
if matches:
    last = matches[-1]
    pos  = last.end()
    content = content[:pos] + zt_jni + content[pos:]
    with open(path, 'w') as f:
        f.write(content)
    print("  4 fungsi zt* ditambahkan ke NetPlayManager.kt")
else:
    # Fallback: sisipkan sebelum closing brace companion object
    # Cari pola "companion object" dan closing brace-nya
    co_match = re.search(r'companion object\s*\{', content)
    if co_match:
        # Cari closing brace companion object
        start = co_match.end()
        depth = 1
        pos   = start
        while pos < len(content) and depth > 0:
            if content[pos] == '{': depth += 1
            elif content[pos] == '}': depth -= 1
            pos += 1
        # Sisipkan sebelum closing brace companion object
        insert_pos = pos - 1
        content = content[:insert_pos] + zt_jni + content[insert_pos:]
        with open(path, 'w') as f:
            f.write(content)
        print("  4 fungsi zt* ditambahkan ke companion object NetPlayManager.kt")
    else:
        print("  WARN: Tidak bisa menemukan titik insert di NetPlayManager.kt")
PYEOF

    python3 "$PATCH_PY2" "$NETPLAY_MGR"
    rm -f "$PATCH_PY2"
    success "NetPlayManager.kt: tambah ztInit/ztShutdown/ztGetAssignedIP/ztIsReady"
else
    info "NetPlayManager.kt: ztInit sudah ada, cek apakah ada typo..."

    # Verifikasi semua 4 fungsi ada
    PATCH_PY3=$(mktemp /tmp/verify_kt_XXXXXX.py)
    cat > "$PATCH_PY3" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

missing = []
for fn in ['ztInit', 'ztShutdown', 'ztGetAssignedIP', 'ztIsReady']:
    if fn not in content:
        missing.append(fn)

if missing:
    print(f"  WARN: Fungsi berikut tidak ditemukan: {missing}")
else:
    print("  Semua 4 fungsi zt* sudah ada")
PYEOF
    python3 "$PATCH_PY3" "$NETPLAY_MGR"
    rm -f "$PATCH_PY3"
fi

# ════════════════════════════════════════════════════════════════════
# BONUS: Verifikasi ZeroTierManager.kt memanggil fungsi yang benar
# ════════════════════════════════════════════════════════════════════
info "Verifikasi ZeroTierManager.kt..."
ZT_MGR="$UTILS_DIR/ZeroTierManager.kt"
if [ -f "$ZT_MGR" ]; then
    PATCH_PY4=$(mktemp /tmp/verify_ztmgr_XXXXXX.py)
    cat > "$PATCH_PY4" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Pastikan pemanggilan menggunakan NetPlayManager.ztXxx() bukan ztXxx() langsung
fixes = 0
for old, new in [
    ('ztInit(', 'NetPlayManager.ztInit('),
    ('ztShutdown()', 'NetPlayManager.ztShutdown()'),
    ('ztGetAssignedIP()', 'NetPlayManager.ztGetAssignedIP()'),
    ('ztIsReady()', 'NetPlayManager.ztIsReady()'),
]:
    if old in content and new not in content:
        content = content.replace(old, new)
        fixes += 1

if fixes > 0:
    with open(path, 'w') as f:
        f.write(content)
    print(f"  ZeroTierManager.kt: {fixes} referensi diperbaiki → NetPlayManager.ztXxx()")
else:
    print("  ZeroTierManager.kt: OK")
PYEOF
    python3 "$PATCH_PY4" "$ZT_MGR"
    rm -f "$PATCH_PY4"
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Fix selesai!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Langkah selanjutnya:"
echo "  git add ."
echo "  git commit -m \"fix: ZeroTierDialog Context bukan Activity + tambah zt* JNI di NetPlayManager\""
echo "  git push origin DevElderLost-patch-4"
echo ""
