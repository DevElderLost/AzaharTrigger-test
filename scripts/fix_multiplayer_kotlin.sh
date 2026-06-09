#!/usr/bin/env bash
# =============================================================================
# fix_multiplayer_kotlin.sh
# Menambahkan deklarasi external fun shutdownMultiplayer() di NativeLibrary.kt
# dan memanggil shutdownMultiplayer() di lifecycle yang tepat di EmulationActivity.kt
#
# Merupakan bagian dari seri fix_multiplayer_bugs.sh (C++ side).
# Jalankan SETELAH fix_multiplayer_bugs.sh berhasil.
# =============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; }
step()    { echo -e "\n${CYAN}════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}════════════════════════════════════════${NC}"; }

# ──────────────────────────────────────────────────────────────────────────────
# FASE 0 — PENCARIAN FILE OTOMATIS
# ──────────────────────────────────────────────────────────────────────────────
step "FASE 0: Mencari lokasi file Kotlin yang relevan..."

SEARCH_ROOT="${1:-$(pwd)}"
info "Root pencarian: $SEARCH_ROOT"

find_file() {
    local label="$1"; local pattern="$2"; local filename_hint="$3"
    local result
    # Cari dengan filter nama file dulu
    result=$(grep -rl "$pattern" "$SEARCH_ROOT" 2>/dev/null \
        | grep -E "(^|/)${filename_hint}$" | head -1)
    # Fallback tanpa filter nama
    if [ -z "$result" ]; then
        result=$(grep -rl "$pattern" "$SEARCH_ROOT" 2>/dev/null | head -1)
    fi
    if [ -z "$result" ]; then
        error "Tidak ditemukan: $label (pattern: '$pattern')"
        return 1
    fi
    echo "$result"
}

FILE_NATIVE_KT=$(find_file "NativeLibrary.kt" \
    "external fun initMultiplayer" \
    "NativeLibrary.kt") || {
    error "NativeLibrary.kt tidak ditemukan."
    error "Pastikan repo sudah di-clone dan kamu jalankan dari root repo."
    exit 1
}

FILE_EMULATION_KT=$(find_file "EmulationActivity.kt" \
    "class EmulationActivity : AppCompatActivity" \
    "EmulationActivity.kt") || {
    error "EmulationActivity.kt tidak ditemukan."
    exit 1
}

echo ""
success "File ditemukan:"
echo "  NativeLibrary.kt    → $FILE_NATIVE_KT"
echo "  EmulationActivity.kt → $FILE_EMULATION_KT"

# ──────────────────────────────────────────────────────────────────────────────
# FASE 1 — CEK IDEMPOTEN (sudah diterapkan sebelumnya?)
# ──────────────────────────────────────────────────────────────────────────────
step "FASE 1: Validasi idempoten..."

PATCH_KT1_DONE=0   # NativeLibrary.kt: deklarasi shutdownMultiplayer
PATCH_KT2_DONE=0   # EmulationActivity.kt: onDestroy
PATCH_KT3_DONE=0   # EmulationActivity.kt: onNewIntent

grep -q "external fun shutdownMultiplayer" "$FILE_NATIVE_KT" 2>/dev/null && {
    warn "Patch NativeLibrary.kt sudah diterapkan — dilewati."
    PATCH_KT1_DONE=1
}
grep -q "shutdownMultiplayer" "$FILE_EMULATION_KT" 2>/dev/null && {
    warn "Patch EmulationActivity.kt sudah diterapkan — dilewati."
    PATCH_KT2_DONE=1; PATCH_KT3_DONE=1
}

if [ "$PATCH_KT1_DONE" -eq 1 ] && [ "$PATCH_KT2_DONE" -eq 1 ]; then
    success "Semua patch Kotlin sudah diterapkan sebelumnya. Tidak ada yang perlu dilakukan."
    exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# FASE 2 — BACKUP
# ──────────────────────────────────────────────────────────────────────────────
step "FASE 2: Membuat backup..."

BACKUP_DIR="$(dirname "$FILE_NATIVE_KT")/kotlin_patch_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp "$FILE_NATIVE_KT"    "$BACKUP_DIR/NativeLibrary.kt.orig"
cp "$FILE_EMULATION_KT" "$BACKUP_DIR/EmulationActivity.kt.orig"
success "Backup tersimpan di: $BACKUP_DIR"

# ──────────────────────────────────────────────────────────────────────────────
# HELPER: replace via Python (aman terhadap karakter spesial)
# ──────────────────────────────────────────────────────────────────────────────
py_replace() {
    python3 - "$1" "$2" "$3" <<'PYEOF'
import sys
filepath, old_file, new_file = sys.argv[1], sys.argv[2], sys.argv[3]
with open(filepath, 'r', encoding='utf-8') as f: content = f.read()
with open(old_file, 'r', encoding='utf-8') as f: old = f.read()
with open(new_file, 'r', encoding='utf-8') as f: new = f.read()
if old not in content:
    print(f"[PYTHON] GAGAL: pattern tidak ditemukan di {filepath}", file=sys.stderr)
    sys.exit(1)
count = content.count(old)
if count > 1:
    print(f"[PYTHON] WARN: pattern ditemukan {count}x, hanya replace pertama", file=sys.stderr)
with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content.replace(old, new, 1))
print(f"[PYTHON] OK: patch diterapkan ke {filepath}")
PYEOF
}

# ──────────────────────────────────────────────────────────────────────────────
# PATCH KT-1 — NativeLibrary.kt: Tambah deklarasi external fun shutdownMultiplayer()
# Letakkan tepat setelah external fun initMultiplayer()
# ──────────────────────────────────────────────────────────────────────────────
step "Patch KT-1: NativeLibrary.kt — Tambah deklarasi shutdownMultiplayer()"

if [ "$PATCH_KT1_DONE" -eq 0 ]; then
    OLD_KT1=$(mktemp); NEW_KT1=$(mktemp)

    # Anchor: baris "external fun initMultiplayer()" yang sudah ada
    cat > "$OLD_KT1" <<'EOF'
    external fun initMultiplayer()
EOF

    cat > "$NEW_KT1" <<'EOF'
    external fun initMultiplayer()

    /**
     * [PATCH-KT1] Menghancurkan semua resource multiplayer:
     * ENetHost, loop thread, dan AnnounceMultiplayerSession.
     * Wajib dipanggil saat emulasi berhenti untuk mencegah memory leak.
     * Pasangan dari initMultiplayer() — dipanggil di onDestroy & onNewIntent.
     */
    external fun shutdownMultiplayer()
EOF

    py_replace "$FILE_NATIVE_KT" "$OLD_KT1" "$NEW_KT1"
    rm -f "$OLD_KT1" "$NEW_KT1"
    success "Patch KT-1 diterapkan."
else
    info "Patch KT-1 dilewati."
fi

# ──────────────────────────────────────────────────────────────────────────────
# PATCH KT-2 — EmulationActivity.kt: onDestroy — panggil shutdownMultiplayer()
# ──────────────────────────────────────────────────────────────────────────────
step "Patch KT-2: EmulationActivity.kt — shutdownMultiplayer() di onDestroy"

if [ "$PATCH_KT2_DONE" -eq 0 ]; then
    OLD_KT2=$(mktemp); NEW_KT2=$(mktemp)

    cat > "$OLD_KT2" <<'EOF'
    override fun onDestroy() {
        EmulationLifecycleUtil.removeHook(onShutdown)
        NativeLibrary.playTimeManagerStop()
        isEmulationRunning = false
        instance = null
        secondaryDisplay.releasePresentation()
        secondaryDisplay.releaseVD()

        super.onDestroy()
    }
EOF

    cat > "$NEW_KT2" <<'EOF'
    override fun onDestroy() {
        EmulationLifecycleUtil.removeHook(onShutdown)
        NativeLibrary.playTimeManagerStop()
        // [PATCH-KT2] Hancurkan semua resource multiplayer sebelum Activity mati.
        // Ini memastikan ENetHost, loop thread, dan AnnounceMultiplayerSession
        // tidak bocor ketika user keluar dari emulasi atau ganti game.
        NativeLibrary.shutdownMultiplayer()
        isEmulationRunning = false
        instance = null
        secondaryDisplay.releasePresentation()
        secondaryDisplay.releaseVD()

        super.onDestroy()
    }
EOF

    py_replace "$FILE_EMULATION_KT" "$OLD_KT2" "$NEW_KT2"
    rm -f "$OLD_KT2" "$NEW_KT2"
    success "Patch KT-2 (onDestroy) diterapkan."
fi

# ──────────────────────────────────────────────────────────────────────────────
# PATCH KT-3 — EmulationActivity.kt: onNewIntent — panggil shutdownMultiplayer()
# sebelum stopEmulation() agar state bersih saat ganti game tanpa keluar Activity
# ──────────────────────────────────────────────────────────────────────────────
step "Patch KT-3: EmulationActivity.kt — shutdownMultiplayer() di onNewIntent"

if [ "$PATCH_KT3_DONE" -eq 0 ]; then
    OLD_KT3=$(mktemp); NEW_KT3=$(mktemp)

    cat > "$OLD_KT3" <<'EOF'
        NativeLibrary.stopEmulation()
        NativeLibrary.playTimeManagerStop()

        isEmulationReady = false
        isRotationBlocked = true
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LOCKED
        emulationViewModel.setEmulationStarted(false)
EOF

    cat > "$NEW_KT3" <<'EOF'
        // [PATCH-KT3] Shutdown multiplayer SEBELUM stopEmulation saat ganti game.
        // Tanpa ini, koneksi multiplayer sebelumnya masih hidup (ghost connection)
        // dan percobaan join berikutnya mendapat ALREADY_IN_ROOM palsu.
        NativeLibrary.shutdownMultiplayer()
        NativeLibrary.stopEmulation()
        NativeLibrary.playTimeManagerStop()

        isEmulationReady = false
        isRotationBlocked = true
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LOCKED
        emulationViewModel.setEmulationStarted(false)
EOF

    py_replace "$FILE_EMULATION_KT" "$OLD_KT3" "$NEW_KT3"
    rm -f "$OLD_KT3" "$NEW_KT3"
    success "Patch KT-3 (onNewIntent) diterapkan."
fi

# ──────────────────────────────────────────────────────────────────────────────
# FASE AKHIR — Verifikasi
# ──────────────────────────────────────────────────────────────────────────────
step "VERIFIKASI: Memeriksa hasil patch Kotlin..."

FAIL=0

verify() {
    local file="$1"; local marker="$2"; local label="$3"
    if grep -q "$marker" "$file" 2>/dev/null; then
        success "$label ✓"
    else
        error "$label ✗ — tidak ditemukan di $(basename "$file")"
        FAIL=1
    fi
}

verify "$FILE_NATIVE_KT"    "external fun shutdownMultiplayer"   "KT-1: deklarasi shutdownMultiplayer"
verify "$FILE_EMULATION_KT" "PATCH-KT2"                         "KT-2: shutdownMultiplayer di onDestroy"
verify "$FILE_EMULATION_KT" "PATCH-KT3"                         "KT-3: shutdownMultiplayer di onNewIntent"

# Pastikan shutdownMultiplayer muncul 2x di EmulationActivity (onDestroy + onNewIntent)
COUNT=$(grep -c "shutdownMultiplayer" "$FILE_EMULATION_KT" 2>/dev/null || echo 0)
if [ "$COUNT" -ge 2 ]; then
    success "KT: shutdownMultiplayer dipanggil di $COUNT tempat ✓"
else
    warn "KT: shutdownMultiplayer hanya ditemukan $COUNT kali di EmulationActivity (diharapkan ≥ 2)"
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  SEMUA PATCH KOTLIN BERHASIL DITERAPKAN ✓   ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Ringkasan perubahan:${NC}"
    echo ""
    echo -e "  ${YELLOW}NativeLibrary.kt${NC}"
    echo "    + external fun shutdownMultiplayer()"
    echo ""
    echo -e "  ${YELLOW}EmulationActivity.kt — onDestroy()${NC}"
    echo "    + NativeLibrary.shutdownMultiplayer()"
    echo "      (dipanggil sebelum isEmulationRunning = false)"
    echo ""
    echo -e "  ${YELLOW}EmulationActivity.kt — onNewIntent()${NC}"
    echo "    + NativeLibrary.shutdownMultiplayer()"
    echo "      (dipanggil sebelum stopEmulation, bersihkan koneksi lama)"
    echo ""
    echo -e "${YELLOW}Langkah selanjutnya:${NC}"
    echo "  1. Pastikan fix_multiplayer_bugs.sh (C++ side) sudah dijalankan"
    echo "  2. Build ulang project: ./gradlew assembleDebug"
    echo "  3. Backup ada di: $BACKUP_DIR"
else
    echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  BEBERAPA PATCH GAGAL — periksa error di atas ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
    echo "  Restore: cp $BACKUP_DIR/*.orig <lokasi aslinya>"
    exit 1
fi
