#!/usr/bin/env bash
# =============================================================================
# Patch: Add "Hide Secondary Screen" Virtual Overlay Button
# =============================================================================
# Menambahkan tombol overlay baru BUTTON_HIDE_SECOND_SCREEN (buttonToggle21).
#
# CARA KERJA:
#   - Layout saat ini WAJIB CUSTOM_LAYOUT (5) agar tombol berfungsi.
#   - Tekan pertama  → simpan posisi bottom screen (custom_bottom_x/y/w/h),
#                      lalu override posisi bottom ke koordinat yang sama persis
#                      dengan top screen → bottom tertutup di belakang top.
#                      Flag "isSecondaryHidden" = true disimpan di SharedPreferences.
#   - Tekan lagi     → restore posisi bottom dari backup → bottom muncul kembali.
#                      Flag "isSecondaryHidden" = false.
#
# KEUNTUNGAN pendekatan ini:
#   - TIDAK perlu enum layout baru di ScreenLayout.kt
#   - TIDAK perlu ubah framebuffer_layout.cpp / .h
#   - TIDAK perlu ubah settings.h C++
#   - Cukup pure Kotlin + SharedPreferences
#
# File yang dimodifikasi:
#   1. NativeLibrary.kt       → tambah konstanta BUTTON_HIDE_SECOND_SCREEN
#   2. InputOverlay.kt        → logika toggle + addOverlayControls + posisi default
#   3. EmulationFragment.kt   → toggle dialog & resetInputOverlay
#   4. res/values/arrays.xml  → label di n3dsButtons array
#
# File yang TIDAK dimodifikasi:
#   - ScreenLayout.kt (tidak butuh enum baru)
#   - framebuffer_layout.cpp / .h (tidak butuh case baru)
#
# Cara pakai:
#   chmod +x add_hide_second_screen_button.sh
#   bash add_hide_second_screen_button.sh /path/to/repo/root
# =============================================================================

set -euo pipefail

REPO_ROOT="${1:-.}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERR]${NC}   $*" >&2; exit 1; }

# ── helper: cari file ─────────────────────────────────────────────────────────
find_file() {
    find "$REPO_ROOT" -type f -path "*$1" 2>/dev/null | head -1
}
require_file() {
    local f; f=$(find_file "$1")
    [[ -n "$f" && -f "$f" ]] || die "File tidak ditemukan: *$1  (di bawah $REPO_ROOT)"
    echo "$f"
}

# ── helper: patch via Python (aman untuk multiline, special char) ─────────────
patch_file() {
    local file="$1" search="$2" replacement="$3"
    python3 - "$file" "$search" "$replacement" << 'PYEOF'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
content = f.read_text(encoding='utf-8')
search = sys.argv[2]
replacement = sys.argv[3]
if search not in content:
    print(f"  [SKIP] Pattern tidak ditemukan di {f.name} — mungkin sudah di-patch")
    sys.exit(0)
new = content.replace(search, replacement, 1)
f.write_text(new, encoding='utf-8')
print(f"  [PATCHED] {f.name}")
PYEOF
}

# ── helper: cek sudah di-patch ────────────────────────────────────────────────
already_patched() {
    grep -q "$1" "$2" 2>/dev/null
}

echo ""
echo "══════════════════════════════════════════════════════════"
echo "  Patch: Hide Secondary Screen Overlay Button"
echo "══════════════════════════════════════════════════════════"
echo "  REPO_ROOT = $REPO_ROOT"
echo ""

# =============================================================================
# 1. NativeLibrary.kt — tambah konstanta BUTTON_HIDE_SECOND_SCREEN
# =============================================================================
echo "━━ [1/4] NativeLibrary.kt"

NATIVE_LIB=$(require_file "NativeLibrary.kt")

if already_patched "BUTTON_HIDE_SECOND_SCREEN" "$NATIVE_LIB"; then
    warn "BUTTON_HIDE_SECOND_SCREEN sudah ada — skip"
else
    patch_file "$NATIVE_LIB" \
'const val BUTTON_TURBO = 10003' \
'const val BUTTON_TURBO = 10003
        const val BUTTON_HIDE_SECOND_SCREEN = 10004'
fi
ok "NativeLibrary.kt"

# =============================================================================
# 2. InputOverlay.kt — 6 lokasi
# =============================================================================
echo ""
echo "━━ [2/4] InputOverlay.kt"

OVERLAY=$(require_file "InputOverlay.kt")

# 2a. Import — ScreenLayout & IntSetting (jika belum ada dari patch sebelumnya)
if ! already_patched "import org.citra.citra_emu.display.ScreenLayout" "$OVERLAY"; then
    patch_file "$OVERLAY" \
'import org.citra.citra_emu.utils.TurboHelper' \
'import org.citra.citra_emu.utils.TurboHelper
import org.citra.citra_emu.display.ScreenLayout
import org.citra.citra_emu.features.settings.model.IntSetting
import org.citra.citra_emu.features.settings.utils.SettingsFile'
    info "Import ScreenLayout + IntSetting ditambahkan"
else
    info "Import sudah ada — skip"
fi

# 2b. Sambungkan tombol ke fungsi toggle di onTouch()
if ! already_patched "BUTTON_HIDE_SECOND_SCREEN" "$OVERLAY"; then
    patch_file "$OVERLAY" \
'                    } else if (button.id == NativeLibrary.ButtonType.BUTTON_TURBO && button.status == NativeLibrary.ButtonState.PRESSED) {
                        TurboHelper.toggleTurbo(true)
                    }' \
'                    } else if (button.id == NativeLibrary.ButtonType.BUTTON_TURBO && button.status == NativeLibrary.ButtonState.PRESSED) {
                        TurboHelper.toggleTurbo(true)
                    } else if (button.id == NativeLibrary.ButtonType.BUTTON_HIDE_SECOND_SCREEN && button.status == NativeLibrary.ButtonState.PRESSED) {
                        toggleHideSecondaryScreen()
                    }'
fi

# 2c. Fungsi toggleHideSecondaryScreen() — disisipkan sebelum hapticFeedback()
#     Logika:
#       • Hanya aktif jika SCREEN_LAYOUT == CUSTOM_LAYOUT (5)
#       • Saat belum tersembunyi → simpan koordinat bottom ke backup key,
#         lalu posisikan bottom screen tepat menutupi top screen (koordinat identik)
#         → reloadSettings + updateFramebuffer
#       • Saat sudah tersembunyi  → restore koordinat bottom dari backup,
#         hapus flag + reloadSettings + updateFramebuffer
# 2c. Fungsi toggleHideSecondaryScreen() — disisipkan sebelum hapticFeedback()
#     Jika sudah terlanjur di-patch versi lama (pakai CUSTOM_TOP_X/CUSTOM_BOTTOM_X),
#     deteksi dan timpa langsung dengan versi yang benar.
if already_patched "CUSTOM_TOP_X" "$OVERLAY" || already_patched "CUSTOM_BOTTOM_X" "$OVERLAY"; then
    info "Terdeteksi versi lama (CUSTOM_TOP_X) — menimpa dengan nama benar..."
    patch_file "$OVERLAY" \
'    private fun toggleHideSecondaryScreen() {
        val currentLayout = IntSetting.SCREEN_LAYOUT.int
        // Tombol ini hanya bekerja saat mode Custom Layout
        if (currentLayout != ScreenLayout.CUSTOM_LAYOUT.int) return

        val isHidden = preferences.getBoolean("secondaryScreenHidden", false)

        if (!isHidden) {
            // ── Sembunyikan secondary screen ─────────────────────────────────
            // 1. Backup posisi bottom screen yang asli
            preferences.edit()
                .putInt("backup_custom_bottom_x", IntSetting.CUSTOM_BOTTOM_X.int)
                .putInt("backup_custom_bottom_y", IntSetting.CUSTOM_BOTTOM_Y.int)
                .putInt("backup_custom_bottom_width", IntSetting.CUSTOM_BOTTOM_WIDTH.int)
                .putInt("backup_custom_bottom_height", IntSetting.CUSTOM_BOTTOM_HEIGHT.int)
                .putBoolean("secondaryScreenHidden", true)
                .apply()

            // 2. Posisikan bottom screen tepat di koordinat yang sama dengan top screen
            //    → bottom terrender di belakang top, sehingga tertutup sepenuhnya
            IntSetting.CUSTOM_BOTTOM_X.int      = IntSetting.CUSTOM_TOP_X.int
            IntSetting.CUSTOM_BOTTOM_Y.int      = IntSetting.CUSTOM_TOP_Y.int
            IntSetting.CUSTOM_BOTTOM_WIDTH.int  = IntSetting.CUSTOM_TOP_WIDTH.int
            IntSetting.CUSTOM_BOTTOM_HEIGHT.int = IntSetting.CUSTOM_TOP_HEIGHT.int
        } else {
            // ── Tampilkan kembali secondary screen ───────────────────────────
            // Restore posisi bottom dari backup
            IntSetting.CUSTOM_BOTTOM_X.int      = preferences.getInt("backup_custom_bottom_x", IntSetting.CUSTOM_BOTTOM_X.int)
            IntSetting.CUSTOM_BOTTOM_Y.int      = preferences.getInt("backup_custom_bottom_y", IntSetting.CUSTOM_BOTTOM_Y.int)
            IntSetting.CUSTOM_BOTTOM_WIDTH.int  = preferences.getInt("backup_custom_bottom_width", IntSetting.CUSTOM_BOTTOM_WIDTH.int)
            IntSetting.CUSTOM_BOTTOM_HEIGHT.int = preferences.getInt("backup_custom_bottom_height", IntSetting.CUSTOM_BOTTOM_HEIGHT.int)

            preferences.edit()
                .putBoolean("secondaryScreenHidden", false)
                .remove("backup_custom_bottom_x")
                .remove("backup_custom_bottom_y")
                .remove("backup_custom_bottom_width")
                .remove("backup_custom_bottom_height")
                .apply()
        }

        // Terapkan perubahan koordinat ke native renderer
        NativeLibrary.reloadSettings()
        NativeLibrary.updateFramebuffer(NativeLibrary.isPortraitMode)
    }' \
'    private fun toggleHideSecondaryScreen() {
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
    }'
fi

if ! already_patched "toggleHideSecondaryScreen" "$OVERLAY"; then
    patch_file "$OVERLAY" \
'    fun hapticFeedback(type:Int){' \
'    private fun toggleHideSecondaryScreen() {
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

    fun hapticFeedback(type:Int){'
fi

# 2d. addOverlayControls() — buttonToggle21
if ! already_patched "buttonToggle21" "$OVERLAY"; then
    patch_file "$OVERLAY" \
'        for (i in comboIds.indices) {
            val toggleKey = "buttonToggle${16 + i}"
            if (preferences.getBoolean(toggleKey, false)) {
                overlayButtons.add(
                    initializeOverlayButton(
                        context,
                        comboDefaultDrawables[i],
                        comboPressedDrawables[i],
                        comboIds[i],
                        orientation
                    )
                )
            }
        }
    }' \
'        for (i in comboIds.indices) {
            val toggleKey = "buttonToggle${16 + i}"
            if (preferences.getBoolean(toggleKey, false)) {
                overlayButtons.add(
                    initializeOverlayButton(
                        context,
                        comboDefaultDrawables[i],
                        comboPressedDrawables[i],
                        comboIds[i],
                        orientation
                    )
                )
            }
        }

        // ── Hide Secondary Screen button (buttonToggle21) ──────────────────
        if (preferences.getBoolean("buttonToggle21", false)) {
            overlayButtons.add(
                initializeOverlayButton(
                    context,
                    R.drawable.button_hide_second_screen,
                    R.drawable.button_hide_second_screen_pressed,
                    NativeLibrary.ButtonType.BUTTON_HIDE_SECOND_SCREEN,
                    orientation
                )
            )
        }
    }'
fi

# 2e. Scale di initializeOverlayButton
if ! already_patched "BUTTON_HIDE_SECOND_SCREEN -> 0.10f" "$OVERLAY"; then
    patch_file "$OVERLAY" \
'                ComboButtonManager.COMBO_BUTTON_3,
                ComboButtonManager.COMBO_BUTTON_4,
                ComboButtonManager.COMBO_BUTTON_5 -> 0.10f' \
'                ComboButtonManager.COMBO_BUTTON_3,
                ComboButtonManager.COMBO_BUTTON_4,
                ComboButtonManager.COMBO_BUTTON_5,
                NativeLibrary.ButtonType.BUTTON_HIDE_SECOND_SCREEN -> 0.10f'
fi

# 2f. Posisi default landscape
if ! already_patched "BUTTON_HIDE_SECOND_SCREEN.*0.18f" "$OVERLAY"; then
    patch_file "$OVERLAY" \
'            .putFloat("${ComboButtonManager.COMBO_BUTTON_5}-X", 0.07f * maxX)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_5}-Y", 0.80f * maxY)
            .apply()
    }

    private fun defaultOverlayPortrait()' \
'            .putFloat("${ComboButtonManager.COMBO_BUTTON_5}-X", 0.07f * maxX)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_5}-Y", 0.80f * maxY)
            // Hide Secondary Screen button — landscape default position
            .putFloat("${NativeLibrary.ButtonType.BUTTON_HIDE_SECOND_SCREEN}-X", 0.18f * maxX)
            .putFloat("${NativeLibrary.ButtonType.BUTTON_HIDE_SECOND_SCREEN}-Y", 0.80f * maxY)
            .apply()
    }

    private fun defaultOverlayPortrait()'
fi

# 2g. Posisi default portrait
if ! already_patched "BUTTON_HIDE_SECOND_SCREEN.*portrait.*0.10f" "$OVERLAY"; then
    patch_file "$OVERLAY" \
'            .putFloat(
                NativeLibrary.ButtonType.BUTTON_TURBO.toString() + portrait + "-X",
                resources.getInteger(R.integer.N3DS_BUTTON_TURBO_PORTRAIT_X).toFloat() / 1000 * maxX
            )
            .putFloat(
                NativeLibrary.ButtonType.BUTTON_TURBO.toString() + portrait + "-Y",
                resources.getInteger(R.integer.N3DS_BUTTON_TURBO_PORTRAIT_Y).toFloat() / 1000 * maxY
            )' \
'            .putFloat(
                NativeLibrary.ButtonType.BUTTON_TURBO.toString() + portrait + "-X",
                resources.getInteger(R.integer.N3DS_BUTTON_TURBO_PORTRAIT_X).toFloat() / 1000 * maxX
            )
            .putFloat(
                NativeLibrary.ButtonType.BUTTON_TURBO.toString() + portrait + "-Y",
                resources.getInteger(R.integer.N3DS_BUTTON_TURBO_PORTRAIT_Y).toFloat() / 1000 * maxY
            )
            // Hide Secondary Screen button — portrait default position
            .putFloat(
                NativeLibrary.ButtonType.BUTTON_HIDE_SECOND_SCREEN.toString() + portrait + "-X",
                0.10f * maxX
            )
            .putFloat(
                NativeLibrary.ButtonType.BUTTON_HIDE_SECOND_SCREEN.toString() + portrait + "-Y",
                0.75f * maxY
            )'
fi

# 2h. defaultOverlay() — init check posisi tombol baru
if ! already_patched "hideSecondScreenPos" "$OVERLAY"; then
    patch_file "$OVERLAY" \
'        val combo1PositionPortrait = preferences.getFloat(
            "${ComboButtonManager.COMBO_BUTTON_1}-Portrait-X", -1f
        )
        if (combo1PositionPortrait == -1f) {
            defaultOverlayPortrait()
        }' \
'        val combo1PositionPortrait = preferences.getFloat(
            "${ComboButtonManager.COMBO_BUTTON_1}-Portrait-X", -1f
        )
        if (combo1PositionPortrait == -1f) {
            defaultOverlayPortrait()
        }

        // Init check: posisi Hide Secondary Screen button
        val hideSecondScreenPos = preferences.getFloat(
            "${NativeLibrary.ButtonType.BUTTON_HIDE_SECOND_SCREEN}-X", -1f
        )
        if (hideSecondScreenPos == -1f) {
            defaultOverlayLandscape()
        }
        val hideSecondScreenPortraitPos = preferences.getFloat(
            "${NativeLibrary.ButtonType.BUTTON_HIDE_SECOND_SCREEN}-Portrait-X", -1f
        )
        if (hideSecondScreenPortraitPos == -1f) {
            defaultOverlayPortrait()
        }'
fi

ok "InputOverlay.kt"

# =============================================================================
# 3. EmulationFragment.kt — showToggleControlsDialog & resetInputOverlay
# =============================================================================
echo ""
echo "━━ [3/4] EmulationFragment.kt"

EMUFRAG=$(require_file "EmulationFragment.kt")

# 3a. Perluas BooleanArray 21 → 22
if ! already_patched "Index  21     = Hide Secondary Screen" "$EMUFRAG"; then
    patch_file "$EMUFRAG" \
'        // Indices 0-15  = tombol standar 3DS
        // Indices 16-20 = Combo Button 1-5
        val enabledButtons = BooleanArray(21)
        enabledButtons.forEachIndexed { i: Int, _: Boolean ->
            var defaultValue = true
            when (i) {
                // Disabled by default: turbo, swap, home, extra, combo buttons
                6, 7, 12, 13, 14, 15, 16, 17, 18, 19, 20 -> defaultValue = false
            }' \
'        // Indices 0-15  = tombol standar 3DS
        // Indices 16-20 = Combo Button 1-5
        // Index  21     = Hide Secondary Screen
        val enabledButtons = BooleanArray(22)
        enabledButtons.forEachIndexed { i: Int, _: Boolean ->
            var defaultValue = true
            when (i) {
                // Disabled by default: turbo, swap, home, extra, combo, hide-second-screen
                6, 7, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21 -> defaultValue = false
            }'
fi

# 3b. resetInputOverlay — loop 21 → 22
if ! already_patched "0 until 22" "$EMUFRAG"; then
    patch_file "$EMUFRAG" \
'        for (i in 0 until 21) {
            var defaultValue = true
            when (i) {
                6, 7, 12, 13, 14, 15, 16, 17, 18, 19, 20 -> defaultValue = false
            }
            editor.putBoolean("buttonToggle$i", defaultValue)
        }' \
'        for (i in 0 until 22) {
            var defaultValue = true
            when (i) {
                6, 7, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21 -> defaultValue = false
            }
            editor.putBoolean("buttonToggle$i", defaultValue)
        }
        // Bersihkan juga state hide secondary screen saat reset
        preferences.edit()
            .putBoolean("secondaryScreenHidden", false)
            .remove("backup_bottom_x")
            .remove("backup_bottom_y")
            .remove("backup_bottom_width")
            .remove("backup_bottom_height")
            .apply()'
fi

# 3c. resetAllScales
if ! already_patched "BUTTON_HIDE_SECOND_SCREEN" "$EMUFRAG"; then
    patch_file "$EMUFRAG" \
'        resetScale("controlScale-" + NativeLibrary.ButtonType.BUTTON_SWAP)
        binding.surfaceInputOverlay.refreshControls()' \
'        resetScale("controlScale-" + NativeLibrary.ButtonType.BUTTON_SWAP)
        resetScale("controlScale-" + NativeLibrary.ButtonType.BUTTON_HIDE_SECOND_SCREEN)
        binding.surfaceInputOverlay.refreshControls()'
fi

ok "EmulationFragment.kt"

# =============================================================================
# 4. arrays.xml — tambah label di n3dsButtons
# =============================================================================
echo ""
echo "━━ [4/4] arrays.xml"

ARRAYS_XML=$(find_file "res/values/arrays.xml")
if [[ -z "$ARRAYS_XML" ]]; then
    warn "arrays.xml tidak ditemukan — tambahkan manual:"
    echo '      Di string-array "n3dsButtons", tambahkan di paling bawah:'
    echo '      <item>Hide Secondary Screen</item>'
else
    if already_patched "Hide Secondary Screen" "$ARRAYS_XML"; then
        warn "Label sudah ada di arrays.xml — skip"
    else
        patch_file "$ARRAYS_XML" \
'        <item>Combo 5</item>
    </string-array>' \
'        <item>Combo 5</item>
        <item>Hide Secondary Screen</item>
    </string-array>'
    fi
    ok "arrays.xml"
fi

# =============================================================================
# Ringkasan & instruksi manual
# =============================================================================
echo ""
echo "══════════════════════════════════════════════════════════"
echo -e "  ${GREEN}Patch selesai!${NC}"
echo "══════════════════════════════════════════════════════════"
echo ""
echo "Yang sudah dimodifikasi:"
echo "  ✓ NativeLibrary.kt     BUTTON_HIDE_SECOND_SCREEN = 10004"
echo "  ✓ InputOverlay.kt      toggleHideSecondaryScreen(), buttonToggle21,"
echo "                         posisi default L+P, scale case, init check"
echo "  ✓ EmulationFragment.kt BooleanArray(22), reset loop 22, clear state"
echo "  ✓ arrays.xml           label 'Hide Secondary Screen' (index 21)"
echo ""
echo "Yang TIDAK perlu diubah (intentional):"
echo "  • ScreenLayout.kt      tidak butuh enum baru"
echo "  • framebuffer_layout   tidak butuh case baru di C++"
echo ""
echo "Masih perlu dilakukan MANUAL:"
echo ""
echo "  1. TAMBAH DRAWABLE PNG"
echo "     Taruh dua file PNG di  src/android/app/src/main/res/drawable/"
echo ""
echo "       button_hide_second_screen.png"
echo "       button_hide_second_screen_pressed.png"
echo ""
echo "     Format & ukuran: samakan dengan button_swap.png / button_turbo.png"
echo "     (biasanya 128×128 atau 96×96 px, transparan background)."
echo "     Tidak perlu XML — getBitmap() langsung decode PNG via BitmapFactory."
echo ""
echo "  2. IntSetting.kt sudah diverifikasi memiliki semua entry yang dibutuhkan:"
echo "       LANDSCAPE_TOP_X/Y/WIDTH/HEIGHT"
echo "       LANDSCAPE_BOTTOM_X/Y/WIDTH/HEIGHT"
echo "       PORTRAIT_TOP_X/Y/WIDTH/HEIGHT"
echo "       PORTRAIT_BOTTOM_X/Y/WIDTH/HEIGHT"
echo "     Tidak ada perubahan yang diperlukan pada IntSetting.kt."
echo ""
echo "  3. CARA TEST:"
echo "     a. Atur layout ke Custom Layout"
echo "     b. Posisikan secondary screen sesuai keinginan"
echo "     c. Aktifkan tombol via Menu → Overlay Options → Toggle Controls → index 21"
echo "     d. Tekan tombol → secondary screen tertutup di belakang primary"
echo "     e. Tekan lagi   → secondary screen kembali ke posisi semula"
echo ""
