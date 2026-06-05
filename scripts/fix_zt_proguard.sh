#!/bin/bash
# fix_zt_proguard.sh — Tambah ProGuard rules untuk ZeroTier
# agar class dan method tidak diobfuskasi/dihapus
#
# Cara pakai:
#   bash scripts/fix_zt_proguard.sh

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
ANDROID_APP="$PROJECT_ROOT/src/android/app"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix: Tambah ProGuard rules untuk ZeroTier"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Cari file ProGuard yang ada ─────────────────────────────────
PROGUARD_FILE=""
for f in \
    "$ANDROID_APP/proguard-rules.pro" \
    "$ANDROID_APP/src/main/proguard-rules.pro" \
    "$PROJECT_ROOT/src/android/proguard-rules.pro"; do
    if [ -f "$f" ]; then
        PROGUARD_FILE="$f"
        break
    fi
done

if [ -z "$PROGUARD_FILE" ]; then
    # Buat file baru
    PROGUARD_FILE="$ANDROID_APP/proguard-rules.pro"
    info "Membuat file baru: $PROGUARD_FILE"
    touch "$PROGUARD_FILE"
fi
info "ProGuard file: $PROGUARD_FILE"

# ── Tambah rules ZeroTier jika belum ada ─────────────────────────
if ! grep -q "zerotier" "$PROGUARD_FILE" 2>/dev/null; then
    cat >> "$PROGUARD_FILE" << 'RULES'

# ── ZeroTier libzt AAR — jangan obfuskasi/hapus ──────────────────
# ZeroTierNative berisi native methods yang dipanggil via JNI
# ZeroTierNode adalah wrapper yang dipanggil via Kotlin reflection
-keep class com.zerotier.** { *; }
-keepclassmembers class com.zerotier.** { *; }
-keepnames class com.zerotier.** { *; }

# Pastikan semua native methods dipertahankan
-keepclasseswithmembernames class * {
    native <methods>;
}

# Pertahankan nama method yang dipanggil via reflection
-keepclassmembers class com.zerotier.sockets.ZeroTierNative {
    public static <methods>;
}
-keepclassmembers class com.zerotier.sockets.ZeroTierNode {
    public <methods>;
}
RULES
    success "ProGuard rules ditambahkan: $PROGUARD_FILE"
else
    info "ProGuard rules ZeroTier sudah ada, skip"
fi

# ── Pastikan proguard-rules.pro dipakai di build.gradle ──────────
GRADLE_KTS="$ANDROID_APP/build.gradle.kts"
GRADLE_GRV="$ANDROID_APP/build.gradle"

GRADLE_FILE=""
[ -f "$GRADLE_KTS" ] && GRADLE_FILE="$GRADLE_KTS"
[ -z "$GRADLE_FILE" ] && [ -f "$GRADLE_GRV" ] && GRADLE_FILE="$GRADLE_GRV"

if [ -n "$GRADLE_FILE" ]; then
    info "Cek build.gradle: $GRADLE_FILE"
    if grep -q "proguardFiles" "$GRADLE_FILE"; then
        # Pastikan proguard-rules.pro ada di daftar
        if ! grep -q "proguard-rules.pro" "$GRADLE_FILE"; then
            python3 - "$GRADLE_FILE" << 'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()
# Tambah proguard-rules.pro ke getDefaultProguardFile line
old = 'getDefaultProguardFile("proguard-android-optimize.txt")'
new = 'getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro"'
if old in content and 'proguard-rules.pro' not in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print("  proguard-rules.pro ditambahkan ke build.gradle")
else:
    print("  Tidak perlu update build.gradle")
PYEOF
        else
            info "proguard-rules.pro sudah ada di build.gradle"
        fi
    else
        info "proguardFiles tidak ditemukan di build.gradle, skip"
    fi
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Fix selesai!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: tambah ProGuard rules untuk ZeroTier agar tidak diobfuskasi\""
echo "  git push origin DevElderLost-patch-4"
echo ""
