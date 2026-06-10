#!/bin/bash
# fix_chain_assign_robust.sh
# Fix: "no viable overloaded '='" — chain assignment cb_* di multiplayer.cpp

set -euo pipefail
REPO="${1:-.}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err_exit() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# Cari multiplayer.cpp — exclude build/, .git/, backup folder, dan file .bak
# Prioritaskan src/android path
MULTIPLAYER_CPP=$(find "$REPO" -type f -name "multiplayer.cpp" \
    ! -path "*/build/*" \
    ! -path "*/.git/*" \
    ! -path "*backup*" \
    ! -path "*.bak*" \
    ! -name "*.bak*" \
    2>/dev/null \
    | grep -v "backup" \
    | sort \
    | head -1)

[[ -z "$MULTIPLAYER_CPP" ]] && err_exit "multiplayer.cpp tidak ditemukan di: $REPO"
info "Target: $MULTIPLAYER_CPP"

# Cek apakah masalah ada
if ! grep -qE 'cb_[a-z]+ = cb_[a-z]+' "$MULTIPLAYER_CPP" 2>/dev/null; then
    ok "Tidak ada chain assignment cb_* — file sudah benar, tidak perlu fix."
    exit 0
fi

info "Memperbaiki chain assignment nullptr..."

python3 - "$MULTIPLAYER_CPP" << 'PYEOF'
import re, sys, shutil, os
from datetime import datetime

path = sys.argv[1]

# Backup di folder yang SAMA dengan file target
backup = path + ".bak_chainfix_" + datetime.now().strftime("%Y%m%d_%H%M%S")
shutil.copy2(path, backup)
print(f"Backup: {backup}")

with open(path, 'r') as f:
    lines = f.readlines()

changed = 0
output = []
for i, line in enumerate(lines, 1):
    # Match: <indent>cb_X = cb_Y = ... = nullptr;
    m = re.match(r'^(\s*)(cb_\w+(?:\s*=\s*cb_\w+)+\s*=\s*nullptr\s*;)', line.rstrip())
    if m:
        indent = m.group(1)
        chain_part = m.group(2)
        varnames = re.findall(r'(cb_\w+)\s*=', chain_part)
        if len(varnames) > 1:
            new_lines = [f"{indent}{v}  = nullptr;\n" for v in varnames]
            output.extend(new_lines)
            changed += 1
            print(f"  Baris {i}: '{line.strip()}'")
            print(f"  → dipecah jadi {len(varnames)} assignment terpisah")
            continue
    output.append(line)

if changed:
    with open(path, 'w') as f:
        f.writelines(output)
    print(f"OK  {changed} chain assignment diperbaiki di: {path}")
else:
    print(f"SKIP: pattern chain assignment tidak ditemukan di baris manapun")
    # Debug: tampilkan semua baris yang ada cb_
    for i, ln in enumerate(lines, 1):
        if 'cb_' in ln and '=' in ln:
            print(f"  Debug baris {i}: {ln.rstrip()}")
PYEOF

echo ""
ok "Selesai. Lakukan:"
echo "  git add src/android/app/src/main/jni/multiplayer.cpp"
echo "  git commit -m 'fix: separate nullptr assignment in UnbindCallbacks'"
echo "  git push"
