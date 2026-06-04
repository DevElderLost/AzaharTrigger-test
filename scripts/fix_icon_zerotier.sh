#!/bin/bash
# fix_icon_zerotier.sh — Hapus app:icon dari btnZeroTier,
# samakan style dengan btnLobbyBrowser
#
# Cara pakai:
#   bash scripts/fix_icon_zerotier.sh

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
LAYOUT_DIR="$PROJECT_ROOT/src/android/app/src/main/res/layout"
CONNECT_XML="$LAYOUT_DIR/dialog_multiplayer_connect.xml"

[ -f "$CONNECT_XML" ] || error "File tidak ditemukan: $CONNECT_XML"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix btnZeroTier — samakan dengan btnLobbyBrowser"
echo "═══════════════════════════════════════════════════════"
echo ""

cp "$CONNECT_XML" "${CONNECT_XML}.bak"

# Cek style btnLobbyBrowser yang sudah ada untuk dijadikan referensi
info "Style btnLobbyBrowser yang ada:"
grep -A8 "btnLobbyBrowser" "$CONNECT_XML" | head -10 || true

PATCH_PY=$(mktemp /tmp/fix_btn_XXXXXX.py)
cat > "$PATCH_PY" << 'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# ── Cari style btnLobbyBrowser sebagai referensi ──────────────────
# Ambil atribut style dari btnLobbyBrowser
lobby_match = re.search(
    r'android:id="@\+id/btnLobbyBrowser"[^/]*/?>',
    content, re.DOTALL
)
lobby_style = ""
if lobby_match:
    lobby_block = lobby_match.group(0)
    style_match = re.search(r'style="([^"]+)"', lobby_block)
    if style_match:
        lobby_style = style_match.group(1)
    print(f"  Style btnLobbyBrowser: {lobby_style}")

# ── Ganti seluruh blok btnZeroTier dengan versi tanpa icon ────────
# Hapus app:icon dan app:iconGravity, samakan style dengan btnLobbyBrowser
old_btn = re.search(
    r'<com\.google\.android\.material\.button\.MaterialButton[^>]*'
    r'android:id="@\+id/btnZeroTier"[^/]*/?>',
    content, re.DOTALL
)

if old_btn:
    old_block = old_btn.group(0)
    print(f"  Ditemukan btnZeroTier block")

    # Ambil atribut yang perlu dipertahankan
    text_match   = re.search(r'android:text="([^"]+)"', old_block)
    margin_matches = re.findall(r'android:layout_margin\w+="[^"]+"', old_block)

    text_val = text_match.group(0) if text_match else 'android:text="@string/zerotier_button_label"'
    margins  = "\n        ".join(margin_matches) if margin_matches else \
               'android:layout_marginStart="16dp"\n        android:layout_marginEnd="16dp"\n        android:layout_marginBottom="8dp"'

    # Style: pakai style btnLobbyBrowser jika ada, fallback ke OutlinedButton
    style_val = lobby_style if lobby_style else "@style/Widget.Material3.Button.OutlinedButton"

    new_block = f"""<com.google.android.material.button.MaterialButton
        android:id="@+id/btnZeroTier"
        style="{style_val}"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        {margins}
        {text_val} />"""

    content = content.replace(old_block, new_block)
    print("  btnZeroTier berhasil dipatch (tanpa icon)")
else:
    # Fallback: hapus saja app:icon dan app:iconGravity
    print("  Block tidak ditemukan dengan regex, hapus app:icon saja")
    content = re.sub(r'\s*app:icon="[^"]*"', '', content)
    content = re.sub(r'\s*app:iconGravity="[^"]*"', '', content)
    print("  app:icon dan app:iconGravity dihapus")

# Bersihkan juga jika masih ada ic_public atau ic_zerotier yang tidak perlu
content = re.sub(r'\s*app:icon="@drawable/ic_public"', '', content)
content = re.sub(r'\s*app:icon="@drawable/ic_zerotier"', '', content)

with open(path, 'w') as f:
    f.write(content)
print(f"  Selesai: {path}")
PYEOF

python3 "$PATCH_PY" "$CONNECT_XML"
rm -f "$PATCH_PY"

# Verifikasi
if grep -q "ic_public\|ic_zerotier" "$CONNECT_XML"; then
    warn "Masih ada referensi icon, hapus manual..."
    sed -i 's|app:icon="@drawable/ic_public"||g' "$CONNECT_XML"
    sed -i 's|app:icon="@drawable/ic_zerotier"||g' "$CONNECT_XML"
    sed -i 's|app:iconGravity="textStart"||g' "$CONNECT_XML"
fi

grep -q "ic_public\|ic_zerotier" "$CONNECT_XML" \
    && echo -e "${RED}[WARN]${NC} Masih ada referensi icon" \
    || success "Verifikasi OK — tidak ada referensi icon"

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Fix selesai!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Langkah selanjutnya:"
echo "  git add ."
echo "  git commit -m \"fix: hapus icon dari btnZeroTier, samakan style dengan btnLobbyBrowser\""
echo "  git push origin DevElderLost-patch-4"
echo ""
