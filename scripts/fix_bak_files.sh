#!/bin/bash
# fix_bak_files.sh — Hapus semua file .bak dari folder res/
# yang menyebabkan error "file name must end with .xml"
#
# Cara pakai:
#   bash scripts/fix_bak_files.sh

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
RES_DIR="$PROJECT_ROOT/src/android/app/src/main/res"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix: Hapus file .bak dari folder res/"
echo "═══════════════════════════════════════════════════════"
echo ""

# Cari dan hapus semua .bak di dalam res/
info "Mencari file .bak di $RES_DIR..."
BAK_FILES=$(find "$RES_DIR" -name "*.bak" 2>/dev/null)

if [ -z "$BAK_FILES" ]; then
    info "Tidak ada file .bak ditemukan di res/"
else
    echo "$BAK_FILES" | while read f; do
        rm -f "$f"
        success "Dihapus: $f"
    done
fi

# Cari juga .bak di src/ lainnya yang tidak perlu
info "Mencari file .bak lain di src/android..."
find "$PROJECT_ROOT/src/android" -name "*.bak" 2>/dev/null | while read f; do
    rm -f "$f"
    success "Dihapus: $f"
done

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Fix selesai!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Langkah selanjutnya:"
echo "  git add ."
echo "  git commit -m \"fix: hapus file .bak dari folder res/\""
echo "  git push origin DevElderLost-patch-4"
echo ""
