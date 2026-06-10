#!/bin/bash
# fix_multiplayer_chain_assign.sh
# Fix compile error: "no viable overloaded '='" di multiplayer.cpp
#
# Root cause: UnbindCallbacks() menggunakan chain assignment
#   cb_state = cb_error = cb_status = cb_chat = nullptr;
# Ini TIDAK VALID karena CallbackHandle<T> adalah shared_ptr<function<void(const T&)>>
# dan tiap cb_* punya tipe T yang berbeda — tidak bisa chain assign antar tipe berbeda.
# Fix: assign nullptr ke masing-masing secara terpisah.

set -euo pipefail
REPO="${1:-.}"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err_exit() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

find_file() {
    find "$REPO" -type f -name "$1" ! -path "*/build/*" ! -path "*/.git/*" 2>/dev/null | head -1
}

MULTIPLAYER_CPP=$(find_file "multiplayer.cpp")
[[ -z "$MULTIPLAYER_CPP" ]] && err_exit "multiplayer.cpp tidak ditemukan di $REPO"
info "Target: $MULTIPLAYER_CPP"

BACKUP="${MULTIPLAYER_CPP}.bak_chainfix_$(date +%Y%m%d_%H%M%S)"
cp "$MULTIPLAYER_CPP" "$BACKUP"
ok "Backup: $BACKUP"

PATCH_OLD=$(mktemp); PATCH_NEW=$(mktemp)
trap 'rm -f "$PATCH_OLD" "$PATCH_NEW"' EXIT

apply_patch() {
    local file="$1" desc="$2"
    if python3 - "$file" "$PATCH_OLD" "$PATCH_NEW" << 'PYEOF'
import sys
path, old_f, new_f = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path,'r') as f: content = f.read()
with open(old_f,'r') as f: old = f.read()
with open(new_f,'r') as f: new = f.read()
if old not in content: sys.exit(1)
with open(path,'w') as f: f.write(content.replace(old, new, 1))
PYEOF
    then
        ok "✓ $desc"
    else
        warn "⚠ SKIP (pattern tidak ditemukan): $desc"
    fi
}

echo ""
info "Fix chain assignment nullptr di UnbindCallbacks()"

# Chain assignment antar tipe berbeda tidak valid di C++
# shared_ptr<function<void(State&)>> tidak bisa di-assign dari shared_ptr<function<void(Error&)>>
cat > "$PATCH_OLD" << 'OLD'
    } else {
        // RoomMember sudah destroyed, cukup clear handle
        cb_state = cb_error = cb_status = cb_chat = nullptr;
    }
OLD

cat > "$PATCH_NEW" << 'NEW'
    } else {
        // RoomMember sudah destroyed, cukup clear handle masing-masing
        // (chain assignment tidak valid karena tiap CallbackHandle<T> punya tipe berbeda)
        cb_state  = nullptr;
        cb_error  = nullptr;
        cb_status = nullptr;
        cb_chat   = nullptr;
    }
NEW
apply_patch "$MULTIPLAYER_CPP" "UnbindCallbacks: pisah assignment nullptr per-variable"

echo ""
ok "Selesai. Build ulang sekarang."
