#!/usr/bin/env bash
# Fix: Force-replace isi fungsi toggleHideSecondaryScreen di InputOverlay.kt
# Dijalankan jika fungsi sudah ada tapi body-nya kosong atau salah nama IntSetting

set -euo pipefail
REPO_ROOT="${1:-.}"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
die()  { echo -e "${RED}[ERR]${NC}  $*" >&2; exit 1; }

OVERLAY=$(find "$REPO_ROOT" -type f -path "*/overlay/InputOverlay.kt" 2>/dev/null | head -1)
[[ -n "$OVERLAY" ]] || die "InputOverlay.kt tidak ditemukan"
info "Target: $OVERLAY"

# ── Ekstrak baris awal dan akhir fungsi ──────────────────────────────────────
START=$(grep -n "private fun toggleHideSecondaryScreen" "$OVERLAY" | head -1 | cut -d: -f1)
END=$(grep -n "fun hapticFeedback" "$OVERLAY" | head -1 | cut -d: -f1)

[[ -n "$START" ]] || die "Fungsi toggleHideSecondaryScreen tidak ditemukan"
[[ -n "$END"   ]] || die "Fungsi hapticFeedback tidak ditemukan (anchor end)"

info "Fungsi ditemukan di baris $START — $((END-1))"
info "Mengganti dengan versi yang benar..."

# ── Tulis ulang file: hapus baris lama, sisipkan yang baru ───────────────────
python3 - "$OVERLAY" "$START" "$END" << 'PYEOF'
import sys, pathlib

f      = pathlib.Path(sys.argv[1])
start  = int(sys.argv[2]) - 1   # 0-based
end    = int(sys.argv[3]) - 1   # baris hapticFeedback (tidak ikut dihapus)

lines  = f.read_text(encoding='utf-8').splitlines(keepends=True)

NEW_FUNC = '''\
    private fun toggleHideSecondaryScreen() {
        val isPortrait = NativeLibrary.isPortraitMode

        // Tombol ini hanya bekerja saat mode Custom Layout (landscape atau portrait)
        val currentLayout = if (isPortrait)
            IntSetting.PORTRAIT_SCREEN_LAYOUT.int
        else
            IntSetting.SCREEN_LAYOUT.int

        val customLayoutInt = if (isPortrait)
            org.citra.citra_emu.display.PortraitScreenLayout.CUSTOM_PORTRAIT_LAYOUT.int
        else
            ScreenLayout.CUSTOM_LAYOUT.int

        if (currentLayout != customLayoutInt) return

        val isHidden = preferences.getBoolean("secondaryScreenHidden", false)

        if (!isHidden) {
            // ── Sembunyikan secondary screen ─────────────────────────────────
            // 1. Backup posisi bottom screen yang asli
            if (isPortrait) {
                preferences.edit()
                    .putInt("backup_bottom_x",      IntSetting.PORTRAIT_BOTTOM_X.int)
                    .putInt("backup_bottom_y",      IntSetting.PORTRAIT_BOTTOM_Y.int)
                    .putInt("backup_bottom_width",  IntSetting.PORTRAIT_BOTTOM_WIDTH.int)
                    .putInt("backup_bottom_height", IntSetting.PORTRAIT_BOTTOM_HEIGHT.int)
                    .putBoolean("secondaryScreenHidden", true)
                    .apply()
                // 2. Override posisi bottom = posisi top → tertutup di belakang top
                IntSetting.PORTRAIT_BOTTOM_X.int      = IntSetting.PORTRAIT_TOP_X.int
                IntSetting.PORTRAIT_BOTTOM_Y.int      = IntSetting.PORTRAIT_TOP_Y.int
                IntSetting.PORTRAIT_BOTTOM_WIDTH.int  = IntSetting.PORTRAIT_TOP_WIDTH.int
                IntSetting.PORTRAIT_BOTTOM_HEIGHT.int = IntSetting.PORTRAIT_TOP_HEIGHT.int
            } else {
                preferences.edit()
                    .putInt("backup_bottom_x",      IntSetting.LANDSCAPE_BOTTOM_X.int)
                    .putInt("backup_bottom_y",      IntSetting.LANDSCAPE_BOTTOM_Y.int)
                    .putInt("backup_bottom_width",  IntSetting.LANDSCAPE_BOTTOM_WIDTH.int)
                    .putInt("backup_bottom_height", IntSetting.LANDSCAPE_BOTTOM_HEIGHT.int)
                    .putBoolean("secondaryScreenHidden", true)
                    .apply()
                // 2. Override posisi bottom = posisi top → tertutup di belakang top
                IntSetting.LANDSCAPE_BOTTOM_X.int      = IntSetting.LANDSCAPE_TOP_X.int
                IntSetting.LANDSCAPE_BOTTOM_Y.int      = IntSetting.LANDSCAPE_TOP_Y.int
                IntSetting.LANDSCAPE_BOTTOM_WIDTH.int  = IntSetting.LANDSCAPE_TOP_WIDTH.int
                IntSetting.LANDSCAPE_BOTTOM_HEIGHT.int = IntSetting.LANDSCAPE_TOP_HEIGHT.int
            }
        } else {
            // ── Tampilkan kembali secondary screen ───────────────────────────
            if (isPortrait) {
                IntSetting.PORTRAIT_BOTTOM_X.int      = preferences.getInt("backup_bottom_x",      IntSetting.PORTRAIT_BOTTOM_X.int)
                IntSetting.PORTRAIT_BOTTOM_Y.int      = preferences.getInt("backup_bottom_y",      IntSetting.PORTRAIT_BOTTOM_Y.int)
                IntSetting.PORTRAIT_BOTTOM_WIDTH.int  = preferences.getInt("backup_bottom_width",  IntSetting.PORTRAIT_BOTTOM_WIDTH.int)
                IntSetting.PORTRAIT_BOTTOM_HEIGHT.int = preferences.getInt("backup_bottom_height", IntSetting.PORTRAIT_BOTTOM_HEIGHT.int)
            } else {
                IntSetting.LANDSCAPE_BOTTOM_X.int      = preferences.getInt("backup_bottom_x",      IntSetting.LANDSCAPE_BOTTOM_X.int)
                IntSetting.LANDSCAPE_BOTTOM_Y.int      = preferences.getInt("backup_bottom_y",      IntSetting.LANDSCAPE_BOTTOM_Y.int)
                IntSetting.LANDSCAPE_BOTTOM_WIDTH.int  = preferences.getInt("backup_bottom_width",  IntSetting.LANDSCAPE_BOTTOM_WIDTH.int)
                IntSetting.LANDSCAPE_BOTTOM_HEIGHT.int = preferences.getInt("backup_bottom_height", IntSetting.LANDSCAPE_BOTTOM_HEIGHT.int)
            }
            preferences.edit()
                .putBoolean("secondaryScreenHidden", false)
                .remove("backup_bottom_x")
                .remove("backup_bottom_y")
                .remove("backup_bottom_width")
                .remove("backup_bottom_height")
                .apply()
        }

        // Terapkan perubahan koordinat ke native renderer
        NativeLibrary.reloadSettings()
        NativeLibrary.updateFramebuffer(isPortrait)
    }

'''

# Ganti baris start..end-1 dengan fungsi baru
new_lines = lines[:start] + [NEW_FUNC] + lines[end:]
f.write_text(''.join(new_lines), encoding='utf-8')
print(f"  Berhasil: baris {start+1}–{end} diganti ({end - start} baris lama → fungsi baru)")
PYEOF

ok "toggleHideSecondaryScreen berhasil diganti"

# ── Verifikasi hasil ──────────────────────────────────────────────────────────
echo ""
info "Verifikasi:"
grep -n "LANDSCAPE_BOTTOM_X\|PORTRAIT_BOTTOM_X" "$OVERLAY" | head -10 \
    && echo "" \
    || echo "  [WARN] Masih tidak ada — cek manual"
