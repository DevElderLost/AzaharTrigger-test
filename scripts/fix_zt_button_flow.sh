#!/bin/bash
# fix_zt_button_flow.sh — Fix alur tombol ZeroTier di NetPlayDialog
# Tombol ZeroTier sekarang langsung buka ZeroTierDialog
# (tidak ada dialog mode tambahan lagi)
#
# Cara pakai:
#   bash scripts/fix_zt_button_flow.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
NETPLAY_DIALOG="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/dialogs/NetPlayDialog.kt"

[ -f "$NETPLAY_DIALOG" ] || { echo "[ERROR] NetPlayDialog.kt tidak ditemukan"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix alur tombol ZeroTier di NetPlayDialog"
echo "═══════════════════════════════════════════════════════"
echo ""

python3 - "$NETPLAY_DIALOG" << 'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# ── Fix 1: btnZeroTier langsung buka ZeroTierDialog ───────────────
# Ganti semua handler btnZeroTier yang ada showZeroTierModeDialog
content = re.sub(
    r'(btnZeroTier\.setOnClickListener\s*\{)[^}]*(showZeroTierModeDialog\(\))[^}]*(\})',
    r'btnZeroTier.setOnClickListener {\n'
    r'                        dismiss()\n'
    r'                        ZeroTierDialog(context).show()\n'
    r'                    }',
    content
)

# ── Fix 2: Hapus fungsi showZeroTierModeDialog() ──────────────────
content = re.sub(
    r'\n\s*private fun showZeroTierModeDialog\(\).*?(?=\n\s*(?:private|fun|override|//|$))',
    '',
    content,
    flags=re.DOTALL
)

# ── Fix 3: Update teks tombol ZeroTier ───────────────────────────
# Jika ZT ready → "ZeroTier ✓", jika tidak → "ZeroTier"
old_text = '''                    if (ZeroTierManager.isReady()) {
                        btnZeroTier.text =
                            context.getString(R.string.zerotier_btn_connected)
                    }'''
new_text = '''                    btnZeroTier.text = if (ZeroTierManager.isReady())
                        "ZeroTier \u2713" else "ZeroTier"'''

if old_text in content:
    content = content.replace(old_text, new_text)

# Fallback regex untuk update teks
content = re.sub(
    r'if \(ZeroTierManager\.isReady\(\)\) \{\s*btnZeroTier\.text\s*=\s*context\.getString\(R\.string\.zerotier_btn_connected\)\s*\}',
    'btnZeroTier.text = if (ZeroTierManager.isReady()) "ZeroTier \u2713" else "ZeroTier"',
    content
)

with open(path, 'w') as f:
    f.write(content)
print("[OK] NetPlayDialog.kt: tombol ZeroTier langsung buka ZeroTierDialog")
PYEOF

echo ""
echo -e "\033[0;32m  Fix selesai!\033[0m"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: tombol ZeroTier langsung buka ZeroTierDialog tanpa dialog mode\""
echo "  git push origin DevElderLost-patch-4"
echo ""
