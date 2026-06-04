#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# apply_cmake_libzt_patch.sh — Patch CMakeLists.txt + build.gradle
# untuk menggunakan libzt-release.aar (tanpa submodule)
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
AAR_FILE="$PROJECT_ROOT/src/android/app/libs/libzt-release.aar"
if [ ! -f "$AAR_FILE" ]; then
    error "File tidak ditemukan: $AAR_FILE\nSalin libzt-release.aar ke src/android/app/libs/ dulu"
fi
success "AAR ditemukan: $AAR_FILE"

# ── Cari CMakeLists.txt yang benar (src/CMakeLists.txt) ─────────────
CMAKE_CANDIDATES=(
    "$PROJECT_ROOT/src/CMakeLists.txt"
    "$PROJECT_ROOT/src/android/app/CMakeLists.txt"
    "$PROJECT_ROOT/CMakeLists.txt"
)

CMAKE_FILE=""
for f in "${CMAKE_CANDIDATES[@]}"; do
    if [ -f "$f" ] && grep -q "citra-android\|add_subdirectory.*jni" "$f" 2>/dev/null; then
        CMAKE_FILE="$f"
        break
    fi
done

if [ -z "$CMAKE_FILE" ]; then
    warn "Tidak bisa auto-detect CMakeLists.txt."
    find "$PROJECT_ROOT/src" -name "CMakeLists.txt" | head -10
    read -rp "Masukkan path lengkap CMakeLists.txt: " CMAKE_FILE
    [ -f "$CMAKE_FILE" ] || error "File tidak ditemukan: $CMAKE_FILE"
fi
info "CMakeLists target: $CMAKE_FILE"

# ── Deteksi nama target ──────────────────────────────────────────────
TARGET_NAME=$(grep -oP "(?<=target_include_directories\()[^\s,)]+" "$CMAKE_FILE" | head -1)
if [ -z "$TARGET_NAME" ]; then
    TARGET_NAME=$(grep -oP "(?<=target_link_libraries\()[^\s,)]+" "$CMAKE_FILE" | head -1)
fi
if [ -z "$TARGET_NAME" ]; then
    TARGET_NAME="citra-android"
    warn "Target tidak terdeteksi, pakai default: $TARGET_NAME"
fi
info "Target: $TARGET_NAME"

# ── Path JNI relatif dari CMakeLists ────────────────────────────────
JNI_REL="\${CMAKE_CURRENT_SOURCE_DIR}/android/app/src/main/jni"

# ── Backup ──────────────────────────────────────────────────────────
cp "$CMAKE_FILE" "${CMAKE_FILE}.bak"
success "Backup: ${CMAKE_FILE}.bak"

# ════════════════════════════════════════════════════════════════════
# PATCH 1: CMakeLists.txt — tambah source ZeroTierNative
# (tidak ada link library C karena pakai AAR dari Gradle)
# ════════════════════════════════════════════════════════════════════
if ! grep -q "ZeroTierNative" "$CMAKE_FILE"; then
    cat >> "$CMAKE_FILE" << EOF

# ── ZeroTier (libzt AAR) — patch oleh apply_cmake_libzt_patch.sh ──────
# libzt-release.aar ditambahkan via build.gradle (fileTree libs/)
# CMakeLists hanya perlu tahu source file ZeroTierNative
target_sources($TARGET_NAME PRIVATE
    $JNI_REL/ZeroTierNative.cpp
    $JNI_REL/ZeroTierNative.h
    $JNI_REL/jni_zt_bridge.cpp
)
# ── End ZeroTier ───────────────────────────────────────────────────────
EOF
    success "CMakeLists.txt: tambah target_sources ZeroTierNative"
else
    warn "CMakeLists.txt: ZeroTierNative sudah ada, skip"
fi

# ════════════════════════════════════════════════════════════════════
# PATCH 2: build.gradle / build.gradle.kts — tambah AAR dependency
# ════════════════════════════════════════════════════════════════════
GRADLE_KTS="$PROJECT_ROOT/src/android/app/build.gradle.kts"
GRADLE_GRV="$PROJECT_ROOT/src/android/app/build.gradle"

if [ -f "$GRADLE_KTS" ]; then
    GRADLE_FILE="$GRADLE_KTS"
    info "Gradle file: $GRADLE_FILE (KTS)"
    if ! grep -q "libzt" "$GRADLE_FILE"; then
        cp "$GRADLE_FILE" "${GRADLE_FILE}.bak"
        # Tambah flatDir repositories
        python3 << PYEOF
import re
path = "$GRADLE_FILE"
with open(path, "r") as f:
    content = f.read()

# Tambah flatDir di android {} block jika belum ada
if "flatDir" not in content:
    content = content.replace(
        "android {",
        'android {\n    repositories {\n        flatDir { dirs("libs") }\n    }\n',
        1
    )

# Tambah fileTree dependency di dependencies {}
if "fileTree" not in content:
    content = content.replace(
        "dependencies {",
        'dependencies {\n    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))',
        1
    )

with open(path, "w") as f:
    f.write(content)
print("  build.gradle.kts patched")
PYEOF
        success "build.gradle.kts: tambah AAR fileTree"
    else
        warn "build.gradle.kts: libzt sudah ada, skip"
    fi

elif [ -f "$GRADLE_GRV" ]; then
    GRADLE_FILE="$GRADLE_GRV"
    info "Gradle file: $GRADLE_FILE (Groovy)"
    if ! grep -q "libzt" "$GRADLE_FILE"; then
        cp "$GRADLE_FILE" "${GRADLE_FILE}.bak"
        python3 << PYEOF
path = "$GRADLE_FILE"
with open(path, "r") as f:
    content = f.read()

# Tambah flatDir di android {} block
if "flatDir" not in content:
    content = content.replace(
        "android {",
        "android {\n    repositories {\n        flatDir { dirs 'libs' }\n    }\n",
        1
    )

# Tambah fileTree dependency
if "fileTree" not in content:
    content = content.replace(
        "dependencies {",
        "dependencies {\n    implementation fileTree(dir: 'libs', include: ['*.aar'])",
        1
    )

with open(path, "w") as f:
    f.write(content)
print("  build.gradle patched")
PYEOF
        success "build.gradle: tambah AAR fileTree"
    else
        warn "build.gradle: libzt sudah ada, skip"
    fi
else
    warn "build.gradle tidak ditemukan di src/android/app/ — skip gradle patch"
fi

# ── Verifikasi ──────────────────────────────────────────────────────
grep -q "ZeroTierNative" "$CMAKE_FILE" && success "Verifikasi CMakeLists.txt: OK" || error "CMakeLists patch gagal"

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  CMakeLists + Gradle patch selesai!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  CMakeLists : $CMAKE_FILE"
echo "  Backup     : ${CMAKE_FILE}.bak"
echo "  AAR        : $AAR_FILE"
echo ""
echo "Langkah selanjutnya:"
echo "  ./gradlew assembleDebug"
echo ""
