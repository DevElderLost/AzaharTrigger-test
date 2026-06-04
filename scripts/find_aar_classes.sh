#!/bin/bash
# find_aar_classes.sh — Cari nama class Java yang ada di libzt-release.aar
#
# Cara pakai:
#   bash scripts/find_aar_classes.sh

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
AAR_FILE="$PROJECT_ROOT/src/android/app/libs/libzt-release.aar"

[ -f "$AAR_FILE" ] || error "AAR tidak ditemukan: $AAR_FILE"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Cari nama class di libzt-release.aar"
echo "═══════════════════════════════════════════════════════"
echo ""

WORK_DIR=$(mktemp -d /tmp/aar_inspect_XXXXXX)
info "Extract AAR ke $WORK_DIR..."

# AAR adalah ZIP — extract dulu
cp "$AAR_FILE" "$WORK_DIR/libzt.zip"
cd "$WORK_DIR"
unzip -q libzt.zip

echo ""
info "Isi AAR:"
ls -la "$WORK_DIR/"

# AAR berisi classes.jar
if [ -f "$WORK_DIR/classes.jar" ]; then
    info "Extract classes.jar..."
    mkdir -p "$WORK_DIR/classes"
    cd "$WORK_DIR/classes"
    jar xf "$WORK_DIR/classes.jar" 2>/dev/null || unzip -q "$WORK_DIR/classes.jar"

    echo ""
    info "Semua class yang ditemukan:"
    find "$WORK_DIR/classes" -name "*.class" | \
        sed "s|$WORK_DIR/classes/||" | \
        sed 's|\.class$||' | \
        sed 's|/|.|g' | \
        sort

    echo ""
    info "Class yang mengandung kata 'zero' atau 'zt' atau 'node':"
    find "$WORK_DIR/classes" -name "*.class" | \
        sed "s|$WORK_DIR/classes/||" | \
        sed 's|\.class$||' | \
        sed 's|/|.|g' | \
        grep -i "zero\|libzt\|ztnode\|node\|network" | \
        sort

    echo ""
    info "Method di class utama (pakai javap jika tersedia):"
    # Cari class yang paling mungkin jadi main API
    MAIN_CLASS=$(find "$WORK_DIR/classes" -name "*.class" | \
        grep -i "zero\|ZeroTier\|ZT" | head -1)

    if [ -n "$MAIN_CLASS" ] && command -v javap >/dev/null 2>&1; then
        CLASS_NAME=$(echo "$MAIN_CLASS" | \
            sed "s|$WORK_DIR/classes/||" | \
            sed 's|\.class$||' | \
            sed 's|/|.|g')
        info "Method di $CLASS_NAME:"
        javap -classpath "$WORK_DIR/classes" "$CLASS_NAME" 2>/dev/null | \
            grep "public static\|public void\|public int\|public String\|public boolean" | \
            head -30
    fi
else
    warn "classes.jar tidak ditemukan"
    info "File lain di AAR:"
    find "$WORK_DIR" -type f | head -20
fi

# Cleanup
rm -rf "$WORK_DIR"

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Selesai! Copy nama class di atas${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Setelah tahu nama class yang benar, jalankan:"
echo "  bash scripts/fix_aar_classname.sh <nama.class>"
echo ""
echo "Contoh:"
echo "  bash scripts/fix_aar_classname.sh com.zerotier.libzt.ZeroTierNode"
echo ""
