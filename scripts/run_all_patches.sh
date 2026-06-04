#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# run_all_patches.sh — Jalankan semua patch sekaligus
#
# Cara pakai di GitHub Codespaces (dari root project):
#   bash scripts/run_all_patches.sh
# ═══════════════════════════════════════════════════════════════════

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║   AzaharTrigger — ZeroTier + Multiplayer Bug Fix      ║"
echo "║   Patch Script (menggunakan libzt-release.aar)        ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "  Project root  : $PROJECT_ROOT"
echo "  Lokasi scripts: $SCRIPT_DIR"
echo ""

# ── Cek AAR sudah ada sebelum mulai ────────────────────────────────
AAR_FILE="$PROJECT_ROOT/src/android/app/libs/libzt-release.aar"
if [ ! -f "$AAR_FILE" ]; then
    echo -e "${YELLOW}[WARN]${NC} File AAR belum ditemukan di:"
    echo "  $AAR_FILE"
    echo ""
    echo "Salin file libzt-release.aar ke folder tersebut dulu:"
    echo "  mkdir -p $PROJECT_ROOT/src/android/app/libs"
    echo "  cp /path/to/libzt-release.aar $AAR_FILE"
    echo ""
    read -rp "Sudah disalin? Lanjutkan? (y/N): " aar_ok
    [[ "$aar_ok" =~ ^[Yy]$ ]] || exit 0
    [ -f "$AAR_FILE" ] || error "AAR masih tidak ditemukan. Batalkan."
fi
echo -e "${GREEN}[OK]${NC}   AAR ditemukan: $AAR_FILE"
echo ""

echo "Script yang akan dijalankan:"
echo "  1. scripts/apply_zerotier_patch.sh    — File baru + patch file lama"
echo "  2. scripts/apply_cmake_libzt_patch.sh — Patch CMakeLists + build.gradle"
echo ""
read -rp "Lanjutkan? (y/N): " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Dibatalkan."; exit 0; }

echo ""
info "=== STEP 1: ZeroTier patch ==="
bash "$SCRIPT_DIR/apply_zerotier_patch.sh"

echo ""
info "=== STEP 2: CMakeLists + Gradle patch ==="
bash "$SCRIPT_DIR/apply_cmake_libzt_patch.sh"

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo -e "║  ${GREEN}Semua patch selesai!${NC}                                 ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "Langkah build:"
echo ""
echo "  # Build debug APK"
echo "  ./gradlew assembleDebug"
echo ""
echo "  # Atau build release"
echo "  ./gradlew assembleRelease"
echo ""
