#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# apply_cmake_libzt_patch.sh — Patch CMakeLists.txt + build.gradle
# untuk menggunakan libzt-release.aar (Gradle 8+ compatible)
#
# Cara pakai di GitHub Codespaces (dari root project):
#   bash scripts/apply_cmake_libzt_patch.sh
# ═══════════════════════════════════════════════════════════════════

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  CMakeLists + Gradle libzt AAR Patch — AzaharTrigger"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Validasi AAR sudah ada ──────────────────────────────────────────
AAR_LIBS="$PROJECT_ROOT/src/android/app/libs"
AAR_FILE="$AAR_LIBS/libzt-release.aar"
mkdir -p "$AAR_LIBS"

if [ ! -f "$AAR_FILE" ]; then
    error "File tidak ditemukan: $AAR_FILE\nSalin libzt-release.aar ke $AAR_LIBS/ dulu"
fi
success "AAR ditemukan: $AAR_FILE"

# ── Cari CMakeLists.txt yang benar ──────────────────────────────────
CMAKE_FILE=""
for f in "$PROJECT_ROOT/src/CMakeLists.txt" \
         "$PROJECT_ROOT/src/android/app/CMakeLists.txt" \
         "$PROJECT_ROOT/CMakeLists.txt"; do
    if [ -f "$f" ] && grep -q "citra-android\|add_subdirectory.*jni" "$f" 2>/dev/null; then
        CMAKE_FILE="$f"; break
    fi
done
[ -n "$CMAKE_FILE" ] || error "CMakeLists.txt tidak ditemukan"
info "CMakeLists: $CMAKE_FILE"

# ── Deteksi nama target ──────────────────────────────────────────────
TARGET_NAME=$(grep -oP "(?<=target_include_directories\()[^\s,)]+" "$CMAKE_FILE" | head -1)
[ -n "$TARGET_NAME" ] || TARGET_NAME="citra-android"
info "Target: $TARGET_NAME"

JNI_REL="\${CMAKE_CURRENT_SOURCE_DIR}/android/app/src/main/jni"

# ════════════════════════════════════════════════════════════════════
# PATCH 1: CMakeLists.txt
# ════════════════════════════════════════════════════════════════════
if ! grep -q "ZeroTierNative" "$CMAKE_FILE"; then
    cp "$CMAKE_FILE" "${CMAKE_FILE}.bak"
    cat >> "$CMAKE_FILE" << CMAKEEOF

# ── ZeroTier (libzt AAR) ─────────────────────────────────────────────
# AAR di-load oleh Gradle, CMakeLists hanya daftarkan source C++
target_sources($TARGET_NAME PRIVATE
    $JNI_REL/ZeroTierNative.cpp
    $JNI_REL/ZeroTierNative.h
    $JNI_REL/jni_zt_bridge.cpp
)
# ─────────────────────────────────────────────────────────────────────
CMAKEEOF
    success "CMakeLists.txt: tambah target_sources ZeroTierNative"
else
    warn "CMakeLists.txt: ZeroTierNative sudah ada, skip"
fi

# ════════════════════════════════════════════════════════════════════
# PATCH 2: build.gradle / build.gradle.kts
# Gradle 8+: JANGAN pakai flatDir di build.gradle
# Gunakan implementation(files()) langsung — ini cara yang benar
# ════════════════════════════════════════════════════════════════════

# Tulis python script ke file temp untuk menghindari quoting hell
PATCH_PY=$(mktemp /tmp/gradle_patch_XXXXXX.py)

cat > "$PATCH_PY" << 'PYEOF'
import sys, re

gradle_path = sys.argv[1]
is_kts      = gradle_path.endswith(".kts")

with open(gradle_path, "r") as f:
    content = f.read()

# Jika sudah ada, skip
if "libzt-release.aar" in content:
    print("  Sudah ada, skip")
    sys.exit(0)

# Hapus flatDir block jika ada dari patch sebelumnya yang salah
content = re.sub(
    r"\s*repositories\s*\{[^}]*flatDir[^}]*\}[^}]*\}",
    "",
    content
)

# Tambah dependency — Gradle 8+ cara yang benar: implementation(files())
if is_kts:
    dep = '    implementation(files("libs/libzt-release.aar"))\n'
else:
    dep = "    implementation files('libs/libzt-release.aar')\n"

content = content.replace("dependencies {", "dependencies {\n" + dep, 1)

with open(gradle_path, "w") as f:
    f.write(content)

print("  Patched: " + gradle_path)
PYEOF

# Cari dan patch gradle file
GRADLE_KTS="$PROJECT_ROOT/src/android/app/build.gradle.kts"
GRADLE_GRV="$PROJECT_ROOT/src/android/app/build.gradle"

if [ -f "$GRADLE_KTS" ]; then
    cp "$GRADLE_KTS" "${GRADLE_KTS}.bak"
    python3 "$PATCH_PY" "$GRADLE_KTS"
    success "build.gradle.kts: tambah implementation(files(libzt-release.aar))"
elif [ -f "$GRADLE_GRV" ]; then
    cp "$GRADLE_GRV" "${GRADLE_GRV}.bak"
    python3 "$PATCH_PY" "$GRADLE_GRV"
    success "build.gradle: tambah implementation files(libzt-release.aar)"
else
    warn "build.gradle tidak ditemukan, skip"
fi

rm -f "$PATCH_PY"

# ── Verifikasi ──────────────────────────────────────────────────────
grep -q "ZeroTierNative" "$CMAKE_FILE" \
    && success "Verifikasi CMakeLists.txt: OK" \
    || error "CMakeLists patch gagal"

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Patch selesai!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  CMakeLists : $CMAKE_FILE"
echo "  AAR        : $AAR_FILE"
echo ""
echo "Langkah selanjutnya:"
echo "  ./gradlew assembleDebug"
echo ""
