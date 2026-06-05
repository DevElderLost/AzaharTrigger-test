bash scripts/fix_modelabel.sh

git add .
git commit -m "fix: hapus referensi modeLabel yang tidak ada di layout"
git push origin DevElderLost-patch-4#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
NETPLAY_DIALOG="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/dialogs/NetPlayDialog.kt"

python3 - "$NETPLAY_DIALOG" << 'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Hapus semua blok yang menggunakan binding.modeLabel
content = re.sub(
    r'\s*//[^\n]*[Mm]ode[^\n]*\n\s*try \{[^}]*binding\.modeLabel[^}]*\} catch[^}]*\}',
    '',
    content,
    flags=re.DOTALL
)
content = re.sub(
    r'\s*binding\.modeLabel\.[^\n]+',
    '',
    content
)
content = re.sub(
    r'\s*binding\.modeLabel\.apply \{[^}]+\}',
    '',
    content,
    flags=re.DOTALL
)
# Hapus komentar modeLabel yang tersisa
content = re.sub(r'\s*// modeLabel[^\n]*\n', '\n', content)
content = re.sub(r'\s*// Tampilkan label mode[^\n]*\n', '\n', content)

with open(path, 'w') as f:
    f.write(content)
print("[OK] Semua referensi modeLabel dihapus dari NetPlayDialog.kt")
PYEOF

echo "  git add ."
echo "  git commit -m \"fix: hapus referensi modeLabel yang tidak ada di layout\""
echo "  git push origin DevElderLost-patch-4"
