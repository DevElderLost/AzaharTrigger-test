#!/usr/bin/env bash
# =============================================================================
# apply_combo_buttons.sh
#
# Patches AzaharTrigger source files to add Combo Button 1-5 feature.
# Run from the ROOT of the repository:
#
#   bash apply_combo_buttons.sh
#
# Files modified:
#   app/src/main/java/org/citra/citra_emu/overlay/InputOverlay.kt
#   app/src/main/java/org/citra/citra_emu/NativeLibrary.kt
#   app/src/main/java/org/citra/citra_emu/features/settings/model/Settings.kt
#
# Files created:
#   app/src/main/java/org/citra/citra_emu/overlay/ComboButtonManager.kt
#   app/src/main/java/org/citra/citra_emu/features/settings/ui/ComboButtonSettingsFragment.kt
#   app/src/main/res/drawable/button_combo.xml
#   app/src/main/res/drawable/button_combo_pressed.xml
# =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

# ── Path constants ────────────────────────────────────────────────────────────
OVERLAY_KT="src/android/app/src/main/java/org/citra/citra_emu/overlay/InputOverlay.kt"
NATIVE_KT="src/android/app/src/main/java/org/citra/citra_emu/NativeLibrary.kt"
SETTINGS_KT="src/android/app/src/main/java/org/citra/citra_emu/features/settings/model/Settings.kt"
OVERLAY_DIR="src/android/app/src/main/java/org/citra/citra_emu/overlay"
SETTINGS_UI_DIR="src/android/app/src/main/java/org/citra/citra_emu/features/settings/ui"
DRAWABLE_DIR="src/android/app/src/main/res/drawable"

# ── Verify we are in the repo root ───────────────────────────────────────────
[[ -f "$OVERLAY_KT" ]]   || die "Cannot find $OVERLAY_KT — run from repo root."
[[ -f "$NATIVE_KT" ]]    || die "Cannot find $NATIVE_KT"
[[ -f "$SETTINGS_KT" ]]  || die "Cannot find $SETTINGS_KT"

# ── Helper: idempotency guard ─────────────────────────────────────────────────
already_patched() {
    grep -q "$1" "$2" 2>/dev/null
}

echo ""
echo "========================================"
echo "  AzaharTrigger — Combo Button Patcher  "
echo "========================================"
echo ""

# =============================================================================
# 1. NativeLibrary.kt — add BUTTON_COMBO_1–5 virtual IDs
# =============================================================================
echo ">>> Patching NativeLibrary.kt ..."

if already_patched "BUTTON_COMBO_1" "$NATIVE_KT"; then
    warn "NativeLibrary.kt already patched — skipping."
else
    # Insert after:  const val BUTTON_TURBO = 801
    python3 - "$NATIVE_KT" <<'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()
OLD  = "        const val BUTTON_TURBO = 801"
NEW  = """\
        const val BUTTON_TURBO = 801

        // Virtual IDs for Combo Buttons (handled in InputOverlay, NOT sent to core)
        const val BUTTON_COMBO_1 = 900
        const val BUTTON_COMBO_2 = 901
        const val BUTTON_COMBO_3 = 902
        const val BUTTON_COMBO_4 = 903
        const val BUTTON_COMBO_5 = 904"""
assert OLD in src, f"Anchor not found: {OLD}"
path.write_text(src.replace(OLD, NEW, 1))
print("  written")
PYEOF
    ok "NativeLibrary.kt patched."
fi

# =============================================================================
# 2. Settings.kt — add PREF_COMBO_* constants
# =============================================================================
echo ">>> Patching Settings.kt ..."

if already_patched "PREF_COMBO_1_ENABLED" "$SETTINGS_KT"; then
    warn "Settings.kt already patched — skipping."
else
    python3 - "$SETTINGS_KT" <<'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()
OLD  = '        const val PREF_STATIC_THEME_COLOR = "StaticThemeColor"'
NEW  = '''\
        const val PREF_STATIC_THEME_COLOR = "StaticThemeColor"

        // ── Combo Button preference keys ──────────────────────────────────
        const val PREF_COMBO_1_ENABLED = "combo_button_1_enabled"
        const val PREF_COMBO_2_ENABLED = "combo_button_2_enabled"
        const val PREF_COMBO_3_ENABLED = "combo_button_3_enabled"
        const val PREF_COMBO_4_ENABLED = "combo_button_4_enabled"
        const val PREF_COMBO_5_ENABLED = "combo_button_5_enabled"

        const val PREF_COMBO_1_LABEL   = "combo_button_1_label"
        const val PREF_COMBO_2_LABEL   = "combo_button_2_label"
        const val PREF_COMBO_3_LABEL   = "combo_button_3_label"
        const val PREF_COMBO_4_LABEL   = "combo_button_4_label"
        const val PREF_COMBO_5_LABEL   = "combo_button_5_label"

        const val PREF_COMBO_1_BUTTONS = "combo_button_1_buttons"
        const val PREF_COMBO_2_BUTTONS = "combo_button_2_buttons"
        const val PREF_COMBO_3_BUTTONS = "combo_button_3_buttons"
        const val PREF_COMBO_4_BUTTONS = "combo_button_4_buttons"
        const val PREF_COMBO_5_BUTTONS = "combo_button_5_buttons"'''
assert OLD in src, f"Anchor not found: {OLD}"
path.write_text(src.replace(OLD, NEW, 1))
print("  written")
PYEOF
    ok "Settings.kt patched."
fi

# =============================================================================
# 3. InputOverlay.kt — three independent patches
# =============================================================================
echo ">>> Patching InputOverlay.kt ..."

# ── 3a. Import ────────────────────────────────────────────────────────────────
if already_patched "import org.citra.citra_emu.overlay.ComboButtonManager" "$OVERLAY_KT"; then
    warn "InputOverlay.kt import already present — skipping."
else
    python3 - "$OVERLAY_KT" <<'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()
OLD  = "import org.citra.citra_emu.utils.TurboHelper"
NEW  = "import org.citra.citra_emu.utils.TurboHelper\nimport org.citra.citra_emu.overlay.ComboButtonManager"
assert OLD in src, f"Anchor not found: {OLD}"
path.write_text(src.replace(OLD, NEW, 1))
print("  import written")
PYEOF
    ok "InputOverlay.kt — import added."
fi

# ── 3b. addOverlayControls() — append combo buttons after buttonToggle15 ─────
if already_patched "buttonToggle20" "$OVERLAY_KT"; then
    warn "InputOverlay.kt addOverlayControls already patched — skipping."
else
    python3 - "$OVERLAY_KT" <<'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()
# Anchor = the closing brace of the buttonToggle15 block, followed by the
# closing brace of addOverlayControls itself.
OLD  = """\
        if (preferences.getBoolean(\"buttonToggle15\", false)) {
            overlayButtons.add(
                initializeOverlayButton(
                    context,
                    R.drawable.button_turbo,
                    R.drawable.button_turbo_pressed,
                    NativeLibrary.ButtonType.BUTTON_TURBO,
                    orientation
                )
            )
        }
    }"""
NEW  = """\
        if (preferences.getBoolean("buttonToggle15", false)) {
            overlayButtons.add(
                initializeOverlayButton(
                    context,
                    R.drawable.button_turbo,
                    R.drawable.button_turbo_pressed,
                    NativeLibrary.ButtonType.BUTTON_TURBO,
                    orientation
                )
            )
        }

        // ── Combo Buttons 1–5 (buttonToggle20–24) ────────────────────────
        val comboIds = intArrayOf(
            ComboButtonManager.COMBO_BUTTON_1,
            ComboButtonManager.COMBO_BUTTON_2,
            ComboButtonManager.COMBO_BUTTON_3,
            ComboButtonManager.COMBO_BUTTON_4,
            ComboButtonManager.COMBO_BUTTON_5,
        )
        for (i in comboIds.indices) {
            val slot = i + 1
            val toggleKey = "buttonToggle${20 + i}"
            if (preferences.getBoolean(toggleKey, false) && ComboButtonManager.isEnabled(slot)) {
                overlayButtons.add(
                    initializeOverlayButton(
                        context,
                        R.drawable.button_combo,
                        R.drawable.button_combo_pressed,
                        comboIds[i],
                        orientation
                    )
                )
            }
        }
    }"""
assert OLD in src, "Anchor (buttonToggle15 block + closing brace) not found"
path.write_text(src.replace(OLD, NEW, 1))
print("  addOverlayControls written")
PYEOF
    ok "InputOverlay.kt — addOverlayControls patched."
fi

# ── 3c. onTouch() — replace onGamePadEvent dispatch with combo-aware version ──
if already_patched "ComboButtonManager.isComboButton" "$OVERLAY_KT"; then
    warn "InputOverlay.kt onTouch already patched — skipping."
else
    python3 - "$OVERLAY_KT" <<'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()
OLD  = """\
                    if (button.id == NativeLibrary.ButtonType.BUTTON_SWAP && button.status == NativeLibrary.ButtonState.PRESSED) {
                        swapScreen()
                    }
                    else if (button.id == NativeLibrary.ButtonType.BUTTON_TURBO && button.status == NativeLibrary.ButtonState.PRESSED) {
                        TurboHelper.toggleTurbo(true)
                    }

                    NativeLibrary.onGamePadEvent(
                        NativeLibrary.TouchScreenDevice,
                        button.id,
                        button.status
                    )"""
NEW  = """\
                    if (button.id == NativeLibrary.ButtonType.BUTTON_SWAP && button.status == NativeLibrary.ButtonState.PRESSED) {
                        swapScreen()
                    } else if (button.id == NativeLibrary.ButtonType.BUTTON_TURBO && button.status == NativeLibrary.ButtonState.PRESSED) {
                        TurboHelper.toggleTurbo(true)
                    }

                    if (ComboButtonManager.isComboButton(button.id)) {
                        // Fire all native buttons assigned to this combo slot simultaneously
                        ComboButtonManager.dispatchComboEvent(button.id, button.status)
                    } else {
                        NativeLibrary.onGamePadEvent(
                            NativeLibrary.TouchScreenDevice,
                            button.id,
                            button.status
                        )
                    }"""
assert OLD in src, "Anchor (onGamePadEvent dispatch block) not found"
path.write_text(src.replace(OLD, NEW, 1))
print("  onTouch written")
PYEOF
    ok "InputOverlay.kt — onTouch patched."
fi

# ── 3d. initializeOverlayButton() scale — add COMBO IDs before else branch ───
if already_patched "COMBO_BUTTON_1 -> 0.10f" "$OVERLAY_KT"; then
    warn "InputOverlay.kt scale switch already patched — skipping."
else
    python3 - "$OVERLAY_KT" <<'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()
OLD  = "                else -> 0.11f"
NEW  = """\
                ComboButtonManager.COMBO_BUTTON_1,
                ComboButtonManager.COMBO_BUTTON_2,
                ComboButtonManager.COMBO_BUTTON_3,
                ComboButtonManager.COMBO_BUTTON_4,
                ComboButtonManager.COMBO_BUTTON_5 -> 0.10f

                else -> 0.11f"""
assert OLD in src, f"Anchor not found: {OLD}"
path.write_text(src.replace(OLD, NEW, 1))
print("  scale switch written")
PYEOF
    ok "InputOverlay.kt — scale switch patched."
fi

# ── 3e. defaultOverlayLandscape() — combo default positions ──────────────────
if already_patched "COMBO_BUTTON_1\"-X\"" "$OVERLAY_KT" || already_patched 'COMBO_BUTTON_1}-X' "$OVERLAY_KT"; then
    warn "InputOverlay.kt landscape defaults already patched — skipping."
else
    python3 - "$OVERLAY_KT" <<'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()
# Anchor: the last .putFloat() call inside defaultOverlayLandscape before .apply()
OLD  = """\
            .putFloat(
                NativeLibrary.ButtonType.BUTTON_TURBO.toString() + \"-X\",
                resources.getInteger(R.integer.N3DS_BUTTON_TURBO_X).toFloat() / 1000 * maxX
            )
            .putFloat(
                NativeLibrary.ButtonType.BUTTON_TURBO.toString() + \"-Y\",
                resources.getInteger(R.integer.N3DS_BUTTON_TURBO_Y).toFloat() / 1000 * maxY
            )
            .apply()
    }

    private fun defaultOverlayPortrait()"""
NEW  = """\
            .putFloat(
                NativeLibrary.ButtonType.BUTTON_TURBO.toString() + "-X",
                resources.getInteger(R.integer.N3DS_BUTTON_TURBO_X).toFloat() / 1000 * maxX
            )
            .putFloat(
                NativeLibrary.ButtonType.BUTTON_TURBO.toString() + "-Y",
                resources.getInteger(R.integer.N3DS_BUTTON_TURBO_Y).toFloat() / 1000 * maxY
            )
            // Combo Buttons default positions (landscape) — left side, below joystick
            .putFloat("${ComboButtonManager.COMBO_BUTTON_1}-X", 0.01f * maxX)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_1}-Y", 0.65f * maxY)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_2}-X", 0.07f * maxX)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_2}-Y", 0.65f * maxY)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_3}-X", 0.13f * maxX)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_3}-Y", 0.65f * maxY)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_4}-X", 0.01f * maxX)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_4}-Y", 0.80f * maxY)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_5}-X", 0.07f * maxX)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_5}-Y", 0.80f * maxY)
            .apply()
    }

    private fun defaultOverlayPortrait()"""
assert OLD in src, "Anchor (landscape TURBO_Y .apply()) not found"
path.write_text(src.replace(OLD, NEW, 1))
print("  landscape defaults written")
PYEOF
    ok "InputOverlay.kt — landscape defaults patched."
fi

# ── 3f. defaultOverlayPortrait() — combo default positions ───────────────────
if already_patched 'COMBO_BUTTON_1}$portrait-X' "$OVERLAY_KT" || already_patched "portrait-X\", 0.02f" "$OVERLAY_KT"; then
    warn "InputOverlay.kt portrait defaults already patched — skipping."
else
    python3 - "$OVERLAY_KT" <<'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src  = path.read_text()
OLD  = """\
            .putFloat(
                NativeLibrary.ButtonType.BUTTON_TURBO.toString() + portrait + \"-X\",
                resources.getInteger(R.integer.N3DS_BUTTON_TURBO_PORTRAIT_X).toFloat() / 1000 * maxX
            )
            .putFloat(
                NativeLibrary.ButtonType.BUTTON_TURBO.toString() + portrait + \"-Y\",
                resources.getInteger(R.integer.N3DS_BUTTON_TURBO_PORTRAIT_Y).toFloat() / 1000 * maxY
            )
            .apply()
    }

    override fun isInEditMode"""
NEW  = """\
            .putFloat(
                NativeLibrary.ButtonType.BUTTON_TURBO.toString() + portrait + "-X",
                resources.getInteger(R.integer.N3DS_BUTTON_TURBO_PORTRAIT_X).toFloat() / 1000 * maxX
            )
            .putFloat(
                NativeLibrary.ButtonType.BUTTON_TURBO.toString() + portrait + "-Y",
                resources.getInteger(R.integer.N3DS_BUTTON_TURBO_PORTRAIT_Y).toFloat() / 1000 * maxY
            )
            // Combo Buttons default positions (portrait)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_1}$portrait-X", 0.02f * maxX)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_1}$portrait-Y", 0.75f * maxY)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_2}$portrait-X", 0.12f * maxX)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_2}$portrait-Y", 0.75f * maxY)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_3}$portrait-X", 0.22f * maxX)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_3}$portrait-Y", 0.75f * maxY)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_4}$portrait-X", 0.02f * maxX)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_4}$portrait-Y", 0.85f * maxY)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_5}$portrait-X", 0.12f * maxX)
            .putFloat("${ComboButtonManager.COMBO_BUTTON_5}$portrait-Y", 0.85f * maxY)
            .apply()
    }

    override fun isInEditMode"""
assert OLD in src, "Anchor (portrait TURBO_PORTRAIT_Y .apply()) not found"
path.write_text(src.replace(OLD, NEW, 1))
print("  portrait defaults written")
PYEOF
    ok "InputOverlay.kt — portrait defaults patched."
fi

# =============================================================================
# 4. Create ComboButtonManager.kt
# =============================================================================
COMBO_MGR="$OVERLAY_DIR/ComboButtonManager.kt"
echo ">>> Writing $COMBO_MGR ..."

if [[ -f "$COMBO_MGR" ]]; then
    warn "ComboButtonManager.kt already exists — skipping."
else
mkdir -p "$OVERLAY_DIR"
cat > "$COMBO_MGR" <<'KOTLIN'
// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

package org.citra.citra_emu.overlay

import android.content.SharedPreferences
import androidx.preference.PreferenceManager
import org.citra.citra_emu.CitraApplication
import org.citra.citra_emu.NativeLibrary

/**
 * Manages Combo Buttons (Combo 1–5).
 *
 * Each combo stores up to [MAX_BUTTONS_PER_COMBO] native button IDs.
 * When pressed/released, all assigned buttons are fired simultaneously.
 *
 * SharedPreferences layout (example slot 1):
 *   "combo_button_1_enabled"  → Boolean
 *   "combo_button_1_label"    → String  (custom label; blank = auto)
 *   "combo_button_1_buttons"  → String  (comma-separated IDs, e.g. "700,701")
 */
object ComboButtonManager {

    const val COMBO_COUNT          = 5
    const val MAX_BUTTONS_PER_COMBO = 4

    // Virtual overlay button IDs (900–904, free in ButtonType range)
    const val COMBO_BUTTON_1 = 900
    const val COMBO_BUTTON_2 = 901
    const val COMBO_BUTTON_3 = 902
    const val COMBO_BUTTON_4 = 903
    const val COMBO_BUTTON_5 = 904

    val COMBO_IDS = intArrayOf(
        COMBO_BUTTON_1, COMBO_BUTTON_2, COMBO_BUTTON_3,
        COMBO_BUTTON_4, COMBO_BUTTON_5,
    )

    // SharedPrefs key helpers
    fun enabledKey(slot: Int) = "combo_button_${slot}_enabled"
    fun labelKey(slot: Int)   = "combo_button_${slot}_label"
    fun buttonsKey(slot: Int) = "combo_button_${slot}_buttons"

    private val preferences: SharedPreferences
        get() = PreferenceManager.getDefaultSharedPreferences(CitraApplication.appContext)

    /** Returns true if the given virtual button ID belongs to a combo slot. */
    fun isComboButton(buttonId: Int) = buttonId in COMBO_BUTTON_1..COMBO_BUTTON_5

    /** Returns 1-based slot index (1–5), or -1 if not a combo ID. */
    fun slotForId(buttonId: Int): Int {
        val idx = COMBO_IDS.indexOf(buttonId)
        return if (idx >= 0) idx + 1 else -1
    }

    /** Native button IDs assigned to a slot (1-based). */
    fun getButtonsForSlot(slot: Int): List<Int> {
        val raw = preferences.getString(buttonsKey(slot), "") ?: ""
        if (raw.isBlank()) return emptyList()
        return raw.split(",")
            .mapNotNull { it.trim().toIntOrNull() }
            .distinct()
            .take(MAX_BUTTONS_PER_COMBO)
    }

    /** Persists button assignments for a slot (1-based). */
    fun setButtonsForSlot(slot: Int, buttonIds: List<Int>) {
        preferences.edit()
            .putString(buttonsKey(slot), buttonIds.distinct().take(MAX_BUTTONS_PER_COMBO).joinToString(","))
            .apply()
    }

    /** Display label; falls back to auto-generated "A+B" style. */
    fun getLabelForSlot(slot: Int): String =
        preferences.getString(labelKey(slot), "")
            ?.takeIf { it.isNotBlank() } ?: autoLabel(slot)

    fun setLabelForSlot(slot: Int, label: String?) {
        preferences.edit().putString(labelKey(slot), label ?: "").apply()
    }

    fun isEnabled(slot: Int): Boolean = preferences.getBoolean(enabledKey(slot), false)

    fun setEnabled(slot: Int, enabled: Boolean) {
        preferences.edit().putBoolean(enabledKey(slot), enabled).apply()
    }

    /**
     * Fires all native buttons assigned to the combo slot in one shot.
     * Called from InputOverlay.onTouch() instead of the regular onGamePadEvent.
     */
    fun dispatchComboEvent(buttonId: Int, state: Int) {
        val slot = slotForId(buttonId)
        if (slot < 0) return
        for (nativeBtn in getButtonsForSlot(slot)) {
            NativeLibrary.onGamePadEvent(NativeLibrary.TouchScreenDevice, nativeBtn, state)
        }
    }

    /** Auto-generates a label like "A+B" from current assignments. */
    fun autoLabel(slot: Int): String {
        val ids = getButtonsForSlot(slot)
        return if (ids.isEmpty()) "Combo $slot" else ids.joinToString("+") { buttonShortName(it) }
    }

    fun buttonShortName(id: Int): String = when (id) {
        NativeLibrary.ButtonType.BUTTON_A      -> "A"
        NativeLibrary.ButtonType.BUTTON_B      -> "B"
        NativeLibrary.ButtonType.BUTTON_X      -> "X"
        NativeLibrary.ButtonType.BUTTON_Y      -> "Y"
        NativeLibrary.ButtonType.BUTTON_START  -> "Start"
        NativeLibrary.ButtonType.BUTTON_SELECT -> "Select"
        NativeLibrary.ButtonType.BUTTON_HOME   -> "Home"
        NativeLibrary.ButtonType.TRIGGER_L     -> "L"
        NativeLibrary.ButtonType.TRIGGER_R     -> "R"
        NativeLibrary.ButtonType.BUTTON_ZL     -> "ZL"
        NativeLibrary.ButtonType.BUTTON_ZR     -> "ZR"
        NativeLibrary.ButtonType.DPAD_UP       -> "↑"
        NativeLibrary.ButtonType.DPAD_DOWN     -> "↓"
        NativeLibrary.ButtonType.DPAD_LEFT     -> "←"
        NativeLibrary.ButtonType.DPAD_RIGHT    -> "→"
        else                                   -> "[$id]"
    }

    /** All buttons available for assignment (name → ID). */
    val assignableButtons: List<Pair<String, Int>> = listOf(
        "A"       to NativeLibrary.ButtonType.BUTTON_A,
        "B"       to NativeLibrary.ButtonType.BUTTON_B,
        "X"       to NativeLibrary.ButtonType.BUTTON_X,
        "Y"       to NativeLibrary.ButtonType.BUTTON_Y,
        "L"       to NativeLibrary.ButtonType.TRIGGER_L,
        "R"       to NativeLibrary.ButtonType.TRIGGER_R,
        "ZL"      to NativeLibrary.ButtonType.BUTTON_ZL,
        "ZR"      to NativeLibrary.ButtonType.BUTTON_ZR,
        "Start"   to NativeLibrary.ButtonType.BUTTON_START,
        "Select"  to NativeLibrary.ButtonType.BUTTON_SELECT,
        "D-Up"    to NativeLibrary.ButtonType.DPAD_UP,
        "D-Down"  to NativeLibrary.ButtonType.DPAD_DOWN,
        "D-Left"  to NativeLibrary.ButtonType.DPAD_LEFT,
        "D-Right" to NativeLibrary.ButtonType.DPAD_RIGHT,
    )
}
KOTLIN
    ok "ComboButtonManager.kt created."
fi

# =============================================================================
# 5. Create ComboButtonSettingsFragment.kt
# =============================================================================
COMBO_FRAG="$SETTINGS_UI_DIR/ComboButtonSettingsFragment.kt"
echo ">>> Writing $COMBO_FRAG ..."

if [[ -f "$COMBO_FRAG" ]]; then
    warn "ComboButtonSettingsFragment.kt already exists — skipping."
else
mkdir -p "$SETTINGS_UI_DIR"
cat > "$COMBO_FRAG" <<'KOTLIN'
// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

package org.citra.citra_emu.features.settings.ui

import android.content.Context
import android.graphics.Typeface
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.widget.SwitchCompat
import androidx.fragment.app.Fragment
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import org.citra.citra_emu.overlay.ComboButtonManager

/**
 * Settings screen for configuring Combo Buttons 1–5.
 *
 * Add to nav_graph.xml:
 *   <fragment
 *       android:id="@+id/comboButtonSettingsFragment"
 *       android:name="org.citra.citra_emu.features.settings.ui.ComboButtonSettingsFragment"
 *       android:label="Combo Buttons" />
 *
 * Navigate to it from any fragment:
 *   findNavController().navigate(R.id.action_..._to_comboButtonSettingsFragment)
 */
class ComboButtonSettingsFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View = buildScrollView(requireContext())

    // ── Build UI programmatically (no extra layout XML needed) ───────────────

    private fun buildScrollView(ctx: Context): ScrollView {
        val scroll = ScrollView(ctx).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        val root = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            val p = 16.dp(ctx)
            setPadding(p, p, p, p)
        }
        for (slot in 1..ComboButtonManager.COMBO_COUNT) {
            root.addView(buildSlotCard(ctx, slot))
        }
        scroll.addView(root)
        return scroll
    }

    private fun buildSlotCard(ctx: Context, slot: Int): View {
        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            val p = 12.dp(ctx); val m = 8.dp(ctx)
            setPadding(p, p, p, p)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).also { it.setMargins(0, 0, 0, m) }
            setBackgroundResource(android.R.drawable.dialog_holo_light_frame)
        }

        // Header row: title + enable switch
        val headerRow = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
        val title = TextView(ctx).apply {
            text = "Combo $slot"
            textSize = 18f
            setTypeface(null, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        val enableSwitch = SwitchCompat(ctx).apply {
            text = "Show on overlay"
            isChecked = ComboButtonManager.isEnabled(slot)
            setOnCheckedChangeListener { _, on -> ComboButtonManager.setEnabled(slot, on) }
        }
        headerRow.addView(title)
        headerRow.addView(enableSwitch)
        card.addView(headerRow)

        // Label field
        card.addView(TextView(ctx).apply {
            text = "Custom label (blank = auto)"
            textSize = 12f
            setPadding(0, 8.dp(ctx), 0, 2.dp(ctx))
        })
        val labelField = EditText(ctx).apply {
            val auto = ComboButtonManager.autoLabel(slot)
            hint = auto
            setText(ComboButtonManager.getLabelForSlot(slot).takeIf { it != auto } ?: "")
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            setOnFocusChangeListener { _, focused ->
                if (!focused) ComboButtonManager.setLabelForSlot(slot, text.toString())
            }
        }
        card.addView(labelField)

        // Chips showing assigned buttons
        card.addView(TextView(ctx).apply {
            text = "Assigned (max ${ComboButtonManager.MAX_BUTTONS_PER_COMBO}):"
            textSize = 13f
            setPadding(0, 12.dp(ctx), 0, 4.dp(ctx))
        })
        val chipGroup = ChipGroup(ctx)

        fun refreshChips() {
            chipGroup.removeAllViews()
            val assigned = ComboButtonManager.getButtonsForSlot(slot)
            if (assigned.isEmpty()) {
                chipGroup.addView(Chip(ctx).apply { text = "(none)" })
            } else {
                assigned.forEach { id ->
                    chipGroup.addView(Chip(ctx).apply {
                        text = ComboButtonManager.buttonShortName(id)
                    })
                }
            }
            labelField.hint = ComboButtonManager.autoLabel(slot)
        }

        refreshChips()
        card.addView(chipGroup)

        // Edit button → dialog
        card.addView(Button(ctx).apply {
            text = "Edit buttons…"
            setOnClickListener { showPickerDialog(ctx, slot, ::refreshChips) }
        })

        return card
    }

    private fun showPickerDialog(ctx: Context, slot: Int, onDone: () -> Unit) {
        val assignable = ComboButtonManager.assignableButtons
        val names      = assignable.map { it.first }.toTypedArray()
        val ids        = assignable.map { it.second }
        val selected   = ComboButtonManager.getButtonsForSlot(slot).toMutableSet()
        val checked    = BooleanArray(names.size) { i -> ids[i] in selected }

        MaterialAlertDialogBuilder(ctx)
            .setTitle("Assign buttons — Combo $slot")
            .setMultiChoiceItems(names, checked) { _, which, isChecked ->
                val id = ids[which]
                if (isChecked) {
                    if (selected.size >= ComboButtonManager.MAX_BUTTONS_PER_COMBO) {
                        checked[which] = false
                        Toast.makeText(
                            ctx,
                            "Max ${ComboButtonManager.MAX_BUTTONS_PER_COMBO} buttons",
                            Toast.LENGTH_SHORT
                        ).show()
                    } else selected.add(id)
                } else selected.remove(id)
            }
            .setPositiveButton(android.R.string.ok) { _, _ ->
                ComboButtonManager.setButtonsForSlot(slot, selected.toList())
                onDone()
            }
            .setNeutralButton("Clear all") { _, _ ->
                ComboButtonManager.setButtonsForSlot(slot, emptyList())
                onDone()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun Int.dp(ctx: Context) =
        (this * ctx.resources.displayMetrics.density).toInt()
}
KOTLIN
    ok "ComboButtonSettingsFragment.kt created."
fi

# =============================================================================
# 6. Drawable resources
# =============================================================================
echo ">>> Writing drawable XML files ..."
mkdir -p "$DRAWABLE_DIR"

COMBO_DEFAULT="$DRAWABLE_DIR/button_combo.xml"
if [[ -f "$COMBO_DEFAULT" ]]; then
    warn "button_combo.xml already exists — skipping."
else
cat > "$COMBO_DEFAULT" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="oval">
    <solid android:color="#CC4488FF" />
    <stroke android:width="2dp" android:color="#FFFFFF" />
    <size android:width="48dp" android:height="48dp" />
</shape>
XML
    ok "button_combo.xml created."
fi

COMBO_PRESSED="$DRAWABLE_DIR/button_combo_pressed.xml"
if [[ -f "$COMBO_PRESSED" ]]; then
    warn "button_combo_pressed.xml already exists — skipping."
else
cat > "$COMBO_PRESSED" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="oval">
    <solid android:color="#EE2266CC" />
    <stroke android:width="2dp" android:color="#AAAAAA" />
    <size android:width="48dp" android:height="48dp" />
</shape>
XML
    ok "button_combo_pressed.xml created."
fi

# =============================================================================
# Done
# =============================================================================
echo ""
echo "========================================"
echo -e "${GREEN}  Patch complete!${NC}"
echo "========================================"
echo ""
echo "Remaining manual steps:"
echo "  1. Add string resources to res/values/strings.xml:"
echo "       <string name=\"combo_button_settings\">Combo Buttons</string>"
echo "       <string name=\"combo_button_settings_description\">Configure multi-button combo shortcuts</string>"
echo ""
echo "  2. Add to nav_graph.xml:"
echo "       <fragment android:id=\"@+id/comboButtonSettingsFragment\""
echo "           android:name=\"org.citra.citra_emu.features.settings.ui.ComboButtonSettingsFragment\""
echo "           android:label=\"Combo Buttons\" />"
echo "     + an <action> from whichever fragment navigates to it."
echo ""
echo "  3. Add a HomeSetting entry in HomeSettingsFragment.kt to navigate to"
echo "     comboButtonSettingsFragment."
echo ""
echo "  4. Add SwitchPreferenceCompat entries (buttonToggle20–24) to your"
echo "     overlay button toggle preference screen XML."
echo ""
